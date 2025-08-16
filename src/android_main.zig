const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.generated.zig");
const vk = @import("vulkan");
const c = @import("c_android.zig");
const DynamicLoader = @import("DynamicLoader_linux.zig");
const InstanceManager = @import("InstanceManager.zig");
const DeviceManager = @import("DeviceManager.zig");
const SwapchainManager = @import("SwapchainManager.zig");
const renderer = @import("renderer.zig");

extern fn call_souce_process(state: *c.android_app, s: *c.android_poll_source) void;

// https://ziggit.dev/t/set-debug-level-at-runtime/6196/3
pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
};

// https://github.com/vamolessa/zig-sdl-android-template/blob/master/src/android_main.zig
// make the std.log.<logger> functions write to the android log
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const priority = switch (message_level) {
        .err => c.ANDROID_LOG_ERROR,
        .warn => c.ANDROID_LOG_WARN,
        .info => c.ANDROID_LOG_INFO,
        .debug => c.ANDROID_LOG_DEBUG,
    };
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";

    var buf = std.io.FixedBufferStream([4 * 1024]u8){
        .buffer = undefined,
        .pos = 0,
    };
    var writer = buf.writer();
    writer.print(prefix ++ format, args) catch {};

    if (buf.pos >= buf.buffer.len) {
        buf.pos = buf.buffer.len - 1;
    }
    buf.buffer[buf.pos] = 0;

    _ = c.__android_log_write(priority, "ZIG", &buf.buffer);
}

var g_loader: *const DynamicLoader = undefined;

fn getProcAddress(_: anytype, name: [*:0]const u8) ?*c.VkPfn {
    return @ptrCast(@alignCast(g_loader.getProcAddress(@ptrCast(name))));
}

fn _main_loop(app: *c.android_app, userdata: *UserData) !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // _ = app;
    std.log.info("## main_loop", .{});

    //
    // init vulkan
    //
    const loader = DynamicLoader.init(.{});
    g_loader = &loader;

    var instance_manager = InstanceManager.init(allocator, getProcAddress);
    defer instance_manager.deinit();
    const instance = try instance_manager.create(.{
        .app_name = constants.appname,
        .instance_extensions = &.{ "VK_KHR_surface", "VK_KHR_android_surface" },
        .is_debug = builtin.mode == std.builtin.OptimizeMode.Debug,
    });

    const surface = try instance.createAndroidSurfaceKHR(&.{
        .window = @ptrCast(app.window),
    }, null);
    const picked = try instance_manager.pickPhysicalDevice(&instance, surface) orelse {
        return error.NoSutablePhysicalDevice;
    };
    const format = try SwapchainManager.chooseSwapSurfaceFormat(
        allocator,
        &instance,
        picked.physical_device.physical_device,
        surface,
    );

    var device_manager = DeviceManager.init(
        allocator,
    );
    defer device_manager.deinit();
    const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};
    const device = try device_manager.create(
        &instance,
        picked.physical_device.physical_device,
        picked.graphics_queue_family_index,
        picked.present_queue_family_index,
        &device_extensions,
    );
    const queue = device.getDeviceQueue(picked.graphics_queue_family_index, 0);

    var swapchain = try SwapchainManager.init(
        allocator,
        &instance,
        surface,
        picked.physical_device.physical_device,
        picked.graphics_queue_family_index,
        picked.present_queue_family_index,
        &device,
        format,
        .{ .inherit_bit_khr = true },
    );
    defer swapchain.deinit();

    // frame resource
    const acquired_semaphore = try device.createSemaphore(&.{}, null);
    defer device.destroySemaphore(acquired_semaphore, null);

    const submit_fence = try device.createFence(&.{
        // .flags = .{ .signaled_bit = true },
    }, null);
    defer device.destroyFence(submit_fence, null);

    const pool = try device.createCommandPool(&.{
        .queue_family_index = picked.graphics_queue_family_index,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);
    defer device.destroyCommandPool(pool, null);

    var commandbuffers: [1]vk.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, &commandbuffers);
    defer device.freeCommandBuffers(pool, 1, &commandbuffers);

    var is_running = true;
    while (is_running) {
        while (true) {
            // process all event
            if (!userdata._active) {
                is_running = false;
                break;
            }

            var source: ?*c.android_poll_source = null;
            // timeout 0 for vulkan animation
            const result = c.ALooper_pollOnce(0, null, null, @ptrCast(&source));
            if (result < 0) {
                break;
            }

            if (source) |s| {
                call_souce_process(app, s);
            }
            if (app.destroyRequested != 0) {
                is_running = false;
                break;
            }
        }

        if (try swapchain.acquireNextImageOrCreate(acquired_semaphore, .{ .width = 0, .height = 0 })) |acquired| {
            if (acquired.result != .success) {
                // TODO: resize swapchain
                std.log.warn("acquire: {s}", .{@tagName(acquired.result)});
                break;
            } else {
                try renderer.recordClearImage(
                    &device,
                    commandbuffers[0],
                    acquired.image,
                    std.time.nanoTimestamp(),
                );

                try device.queueSubmit(queue, 1, &.{.{
                    .wait_semaphore_count = 1,
                    .p_wait_semaphores = @ptrCast(&acquired_semaphore),
                    .p_wait_dst_stage_mask = &.{.{
                        .transfer_bit = true,
                        .color_attachment_output_bit = true,
                    }},
                    .command_buffer_count = 1,
                    .p_command_buffers = &commandbuffers,
                }}, submit_fence);
                _ = try device.waitForFences(1, @ptrCast(&submit_fence), vk.TRUE, std.math.maxInt(u64));
                try device.resetFences(1, @ptrCast(&submit_fence));

                try swapchain.present(acquired.image_index, &.{});
            }
        }
    }

    return true;
}

const UserData = struct {
    pApp: ?*c.android_app = null,
    _active: bool = false,
    _window: ?*c.ANativeWindow = null,
    _appName: []const u8,

    fn on_app_cmd(pApp: [*c]c.android_app, cmd: i32) callconv(.c) void {
        var userdata: *UserData = @ptrCast(@alignCast(pApp.*.userData orelse @panic("no userData")));
        switch (cmd) {
            c.APP_CMD_RESUME => {
                std.log.debug("onAppCmd: APP_CMD_RESUME", .{});
                userdata._active = true;
            },
            c.APP_CMD_INIT_WINDOW => {
                std.log.debug("onAppCmd: APP_CMD_INIT_WINDOW", .{});
                userdata._window = pApp.*.window;
            },
            c.APP_CMD_PAUSE => {
                std.log.debug("onAppCmd: APP_CMD_PAUSE", .{});
                userdata._active = false;
            },
            c.APP_CMD_TERM_WINDOW => {
                std.log.debug("onAppCmd: APP_CMD_TERM_WINDOW", .{});
                userdata._window = null;
            },
            else => {
                std.log.debug("onAppCmd: {}: not handled", .{cmd});
            },
        }
    }
};

fn wait_window(app: *c.android_app, userdata: *UserData) bool {
    while (true) {
        var source: ?*c.android_poll_source = null;
        const result = c.ALooper_pollOnce(-1, null, null, @ptrCast(&source));
        if (result == c.ALOOPER_POLL_ERROR) {
            @panic("ALooper_pollOnce returned an error");
        }

        if (source) |s| {
            call_souce_process(app, s);
        }
        if (app.destroyRequested != 0) {
            return true;
        }
        if (userdata._window != null) {
            return false;
        }
    }
}

export fn android_main(app: *c.android_app) callconv(.C) void {
    std.log.info("## {s} ##", .{@tagName(builtin.mode)});
    // const useDebug = builtin.mode == std.builtin.OptimizeMode.Debug;

    var userdata = UserData{
        .pApp = app,
        ._appName = constants.appname,
    };
    app.userData = &userdata;
    app.onAppCmd = &UserData.on_app_cmd;

    while (true) {
        {
            const is_exit = wait_window(app, &userdata);
            if (is_exit) {
                break;
            }
        }

        {
            const is_exit = _main_loop(app, &userdata) catch |err| {
                std.log.err("{}", .{err});
                break;
            };
            if (is_exit) {
                break;
            }
        }
    }
}

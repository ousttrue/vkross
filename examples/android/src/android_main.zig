const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.generated.zig");
const vkross = @import("vkross");
const vk = vkross.vk;
const c = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("GLES/gl.h");
    @cInclude("android/choreographer.h");
    @cInclude("android/log.h");
    @cInclude("android/sensor.h");
    @cInclude("android/set_abort_message.h");
    @cInclude("android_native_app_glue.h");
    // #include <jni.h>
});

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

var g_loader: *const vkross.DynamicLoader = undefined;

pub const VkPfn = fn (*const anyopaque, ?*const anyopaque, *anyopaque) callconv(.c) c_int;
fn getProcAddress(_: anytype, name: [*:0]const u8) ?*VkPfn {
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
    const loader = vkross.DynamicLoader.init(.{});
    g_loader = &loader;

    var instance_manager = vkross.InstanceManager.init(allocator, getProcAddress);
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
    const format = try vkross.SwapchainManager.chooseSwapSurfaceFormat(
        allocator,
        &instance,
        picked.physical_device.physical_device,
        surface,
    );

    var device_manager = vkross.DeviceManager.init(
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

    var swapchain = try vkross.SwapchainManager.init(
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
                try vkross.renderer.recordClearImage(
                    &device,
                    acquired.command_buffer,
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
                    .p_command_buffers = @ptrCast(&acquired.command_buffer),
                }}, acquired.submit_fence);
                _ = try device.waitForFences(1, @ptrCast(&acquired.submit_fence), vk.TRUE, std.math.maxInt(u64));
                try device.resetFences(1, @ptrCast(&acquired.submit_fence));

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

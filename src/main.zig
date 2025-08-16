const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const constants = @import("constants.generated.zig");
const c = @import("c.zig");
const InstanceManager = @import("InstanceManager.zig");
const DeviceManager = @import("DeviceManager.zig");
const SwapchainManager = @import("SwapchainManager.zig");
const renderer = @import("renderer.zig");
const DynamicLoader = if (builtin.target.os.tag == .windows)
    @import("DynamicLoader_win32.zig")
else
    @import("DynamicLoader_linux.zig");

pub extern fn glfwCreateWindowSurface(
    instance: vk.Instance,
    window: *c.GLFWwindow,
    allocation_callbacks: ?*const vk.AllocationCallbacks,
    surface: *vk.SurfaceKHR,
) vk.Result;

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

    switch (message_level) {
        .err => {
            std.debug.print("\x1b[35m[err]{s}\x1b[0m\n", .{buf.buffer});
        },
        .warn => {
            std.debug.print("\x1b[33m[warn]{s}\x1b[0m\n", .{buf.buffer});
        },
        .info => {
            std.debug.print("\x1b[36m[info]{s}\x1b[0m\n", .{buf.buffer});
        },
        .debug => {
            std.debug.print("\x1b[38;5;08m[debug]{s}\x1b[0m\n", .{buf.buffer});
        },
    }
}

var g_loader: *const DynamicLoader = undefined;

fn getProcAddress(_: anytype, name: [*:0]const u8) ?*anyopaque {
    return g_loader.getProcAddress(@ptrCast(name));
}

fn getGlfwFramebufferExtent(window: *c.GLFWwindow) vk.Extent2D {
    var w: c_int = undefined;
    var h: c_int = undefined;
    c.glfwGetFramebufferSize(window, &w, &h);
    return .{ .width = @intCast(w), .height = @intCast(h) };
}

pub fn main() !void {
    const loader = DynamicLoader.init(.{});
    g_loader = &loader;

    std.log.debug("debug", .{});
    std.log.info("info", .{});
    std.log.warn("warn", .{});
    std.log.err("err", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        @intCast(800),
        @intCast(600),
        constants.appname,
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfwDestroyWindow(window);

    //
    // init vulkan
    //
    // var instance_manager = InstanceManager.init(allocator, c.glfwGetInstanceProcAddress);
    var instance_manager = InstanceManager.init(allocator, &getProcAddress);
    defer instance_manager.deinit();
    var glfw_exts_count: u32 = undefined;
    const glfw_instance_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);
    const instance = try instance_manager.create(.{
        .app_name = constants.appname,
        .instance_extensions = @ptrCast(glfw_instance_extensions[0..glfw_exts_count]),
        .is_debug = builtin.mode == std.builtin.OptimizeMode.Debug,
    });

    // VkSurface from glfw
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance.handle, window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }
    defer instance.destroySurfaceKHR(surface, null);

    const picked = try instance_manager.pickPhysicalDevice(&instance, surface) orelse {
        return error.NoSuitablePhysicalDevice;
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
        .{ .opaque_bit_khr = true },
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

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        const extent = getGlfwFramebufferExtent(window);
        if (extent.width == 0 or extent.height == 0) {
            // Don't present or resize swapchain while the window is minimized
            continue;
        }

        const acquired = swapchain.acquireNextImageOrCreate(
            acquired_semaphore,
            extent,
        ) catch |err| {
            @panic(@errorName(err));
        } orelse {
            continue;
        };
        if (acquired.result != .success) {
            // TODO: resize swapchain
            std.log.warn("acquire: {s}", .{@tagName(acquired.result)});
            break;
        }

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

        // TODO: vsync
        std.Thread.sleep(std.time.ns_per_ms * 16);
    }

    try device.deviceWaitIdle();
}

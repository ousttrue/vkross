const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const c = @import("c.zig");
const InstanceManager = @import("InstanceManager.zig");
const DeviceManager = @import("DeviceManager.zig");
const Swapchain = @import("Swapchain.zig");
const renderer = @import("renderer.zig");

pub extern fn glfwCreateWindowSurface(
    instance: vk.Instance,
    window: *c.GLFWwindow,
    allocation_callbacks: ?*const vk.AllocationCallbacks,
    surface: *vk.SurfaceKHR,
) vk.Result;

const app_name: [:0]const u8 = "vulkancross_glfw";

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

pub fn main() !void {
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

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        @intCast(extent.width),
        @intCast(extent.height),
        app_name,
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfwDestroyWindow(window);

    //
    // init vulkan
    //
    var instance_manager = InstanceManager.init(allocator, c.glfwGetInstanceProcAddress);
    defer instance_manager.deinit();

    var glfw_exts_count: u32 = undefined;
    const glfw_instance_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);
    const instance = try instance_manager.create(.{
        .app_name = app_name,
        .instance_extensions = @ptrCast(glfw_instance_extensions[0..glfw_exts_count]),
        .is_debug = builtin.mode == std.builtin.OptimizeMode.Debug,
    });

    // VkSurface from glfw
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance.handle, window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }
    defer instance.destroySurfaceKHR(surface, null);

    // TODO: choose physical device, queue
    const physical_device = instance_manager.physical_devices[0];
    const queue_family_index: u32 = 0;
    const present_queue_family_index: u32 = 0;

    var device_manager = DeviceManager.init(
        allocator,
    );
    defer device_manager.deinit();

    const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};
    const device = try device_manager.create(
        &instance,
        physical_device,
        queue_family_index,
        present_queue_family_index,
        &device_extensions,
    );
    const queue = device.getDeviceQueue(queue_family_index, 0);

    var swapchain = try Swapchain.init(
        allocator,
        &instance,
        surface,
        queue_family_index,
        present_queue_family_index,
        physical_device,
        &device,
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
        .queue_family_index = queue_family_index,
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
        var w: c_int = undefined;
        var h: c_int = undefined;
        c.glfwGetFramebufferSize(window, &w, &h);

        // Don't present or resize swapchain while the window is minimized
        if (w != 0 and h != 0) {
            const acquired = try swapchain.acquireNextImage(acquired_semaphore);
            if (acquired.result != .success) {
                // TODO: resize swapchain
                std.log.warn("acquire: {s}", .{@tagName(acquired.result)});
                break;
            } else {
                try renderer.recordClearImage(&device, commandbuffers[0], acquired.image);

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

                const res = try swapchain.present(acquired.image_index, &.{});
                if (res != .success) {
                    std.log.warn("present: {s}", .{@tagName(res)});
                }
            }

            // wait
            std.Thread.sleep(std.time.ns_per_ms * 16);
        }
    }

    try device.deviceWaitIdle();
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const c = @import("c.zig");
const VulkanDevice = @import("VulkanDevice.zig");

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
    var glfw_exts_count: u32 = undefined;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

    var vulkan_device = try VulkanDevice.init(
        allocator,
        c.glfwGetInstanceProcAddress,
        .{
            .app_name = app_name,
            .instance_extensions = @ptrCast(glfw_exts[0..glfw_exts_count]),
            .is_debug = builtin.mode == std.builtin.OptimizeMode.Debug,
        },
    );
    defer vulkan_device.deinit();

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        var w: c_int = undefined;
        var h: c_int = undefined;
        c.glfwGetFramebufferSize(window, &w, &h);

        // Don't present or resize swapchain while the window is minimized
        if (w != 0 and h != 0) {}
    }
}

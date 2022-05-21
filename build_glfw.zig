const std = @import("std");

const GLFW_SRCS = [_][]const u8{
    "context.c",
    "egl_context.c",
    "init.c",
    "input.c",
    "monitor.c",
    "null_init.c",
    "null_joystick.c",
    "null_monitor.c",
    "null_window.c",
    "osmesa_context.c",
    "platform.c",
    "vulkan.c",
    "window.c",
};

const GLFW_SRCS_WINDOWS = [_][]const u8{
    "wgl_context.c",
    "win32_init.c",
    "win32_joystick.c",
    "win32_module.c",
    "win32_monitor.c",
    "win32_thread.c",
    "win32_time.c",
    "win32_window.c",
};

const GLFW_LIBS_WINDOWS = [_][]const u8{
    "gdi32",
    "user32",
};

pub fn link(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const glfw_dep = b.dependency("glfw", .{});
    exe.addIncludePath(glfw_dep.path("include"));
    exe.addCSourceFiles(.{
        .root = glfw_dep.path("src"),
        .files = &(GLFW_SRCS ++ GLFW_SRCS_WINDOWS),
        .flags = &.{
            "-D_GLFW_WIN32",
        },
    });
    for (GLFW_LIBS_WINDOWS) |lib| {
        exe.linkSystemLibrary(lib);
    }
}

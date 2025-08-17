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

const GLFW_SRCS_LINUX = [_][]const u8{
    "linux_joystick.c",
    "wl_init.c",
    "wl_monitor.c",
    "wl_window.c",
    "posix_poll.c",
    "posix_module.c",
    "posix_time.c",
    "posix_thread.c",
    "xkb_unicode.c",
};

const WaylandXml = struct {
    xml: []const u8,
    header: []const u8,
    gen: []const u8 = "client-header",
};
const WAYLAND_LIST = [_]WaylandXml{
    .{
        .xml = "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
        .header = "xdg-shell-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml",
        .header = "xdg-decoration-unstable-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml",
        .header = "viewporter-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml",
        .header = "relative-pointer-unstable-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml",
        .header = "pointer-constraints-unstable-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml",
        .header = "fractional-scale-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml",
        .header = "xdg-activation-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml",
        .header = "idle-inhibit-unstable-v1-client-protocol.h",
    },
    .{
        .xml = "/usr/share/wayland/wayland.xml",
        .header = "wayland-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
        .header = "xdg-shell-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml",
        .header = "xdg-decoration-unstable-v1-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml",
        .header = "viewporter-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml",
        .header = "relative-pointer-unstable-v1-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml",
        .header = "pointer-constraints-unstable-v1-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml",
        .header = "fractional-scale-v1-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml",
        .header = "xdg-activation-v1-client-protocol-code.h",
        .gen = "public-code",
    },
    .{
        .xml = "/usr/share/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml",
        .header = "idle-inhibit-unstable-v1-client-protocol-code.h",
        .gen = "public-code",
    },
};

const GLFW_LIBS_LINUX = [_][]const u8{};

pub fn link(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    exe: *std.Build.Step.Compile,
) void {
    const glfw_dep = b.dependency("glfw", .{});
    exe.addIncludePath(glfw_dep.path("include"));

    if (target.result.os.tag == .windows) {
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
    } else {
        // Linux + Wayland

        for (WAYLAND_LIST) |w| {
            const cmd = b.addSystemCommand(&.{
                "wayland-scanner",
            });
            cmd.addArg(w.gen);
            cmd.addArg(w.xml);
            const header = cmd.addOutputFileArg(w.header);
            exe.addIncludePath(header.dirname());
            exe.step.dependOn(&cmd.step);
        }

        exe.addCSourceFiles(.{
            .root = glfw_dep.path("src"),
            .files = &(GLFW_SRCS ++ GLFW_SRCS_LINUX),
            .flags = &.{
                "-D_GLFW_WAYLAND",
            },
        });
        for (GLFW_LIBS_LINUX) |lib| {
            exe.linkSystemLibrary(lib);
        }
    }
}

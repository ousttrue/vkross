const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.generated.zig");
const c = @import("c_android.zig");
const DynamicLoader = @import("DynamicLoader_android.zig");
const InstanceManager = @import("InstanceManager.zig");

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
    _ = userdata;
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

    const picked = try instance_manager.pickPhysicalDevice(&instance, surface);
    _ = picked;

    //   // vuloxr::vk::Surface surface(instance, _surface, picked.physicalDevice);
    //
    //   vuloxr::vk::Device device;
    //   device.layers = instance.layers;
    //   device.addExtension(*physicalDevice, "VK_KHR_swapchain");
    //   vuloxr::vk::CheckVkResult(device.create(instance, *physicalDevice,
    //                                           physicalDevice.graphicsFamilyIndex));
    //
    //   vuloxr::vk::Swapchain swapchain(instance, surface, *physicalDevice,
    //                                   *presentFamily, device, device.queueFamily);
    //   swapchain.create();
    //
    //   main_loop(
    //       [userdata, app]().std::optional<vuloxr::gui::WindowState> {
    //         while (true) {
    //           if (!userdata._active) {
    //             return {};
    //           }
    //
    //           struct android_poll_source *source;
    //           int events;
    //           if (ALooper_pollOnce(
    //                   // timeout 0 for vulkan animation
    //                   0, nullptr, &events, (void **)&source) < 0) {
    //             return vuloxr::gui::WindowState{};
    //           }
    //           if (source) {
    //             source.process(app, source);
    //           }
    //           if (app.destroyRequested) {
    //             return {};
    //           }
    //         }
    //       },
    //       instance, swapchain, *physicalDevice, device, nullptr);
    //
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
                std.log.debug("# APP_CMD_RESUME", .{});
                userdata._active = true;
            },
            c.APP_CMD_INIT_WINDOW => {
                std.log.debug("# APP_CMD_INIT_WINDOW", .{});
                userdata._window = pApp.*.window;
            },
            c.APP_CMD_PAUSE => {
                std.log.debug("# APP_CMD_PAUSE", .{});
                userdata._active = false;
            },
            c.APP_CMD_TERM_WINDOW => {
                std.log.debug("# APP_CMD_TERM_WINDOW", .{});
                userdata._window = null;
            },
            else => {
                std.log.debug("# {}: not handled", .{cmd});
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

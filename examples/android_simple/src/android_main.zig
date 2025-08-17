const std = @import("std");
const c = @import("c.zig");

fn CHECK_NOT_NULL(p: ?*const anyopaque) void {
    if (p == null) {
        @panic("null !");
    }
}

// for log message @tagName
const AppCmd = enum(c_int) {
    APP_CMD_INPUT_CHANGED = c.APP_CMD_INPUT_CHANGED,
    APP_CMD_INIT_WINDOW = c.APP_CMD_INIT_WINDOW,
    APP_CMD_TERM_WINDOW = c.APP_CMD_TERM_WINDOW,
    APP_CMD_WINDOW_RESIZED = c.APP_CMD_WINDOW_RESIZED,
    APP_CMD_WINDOW_REDRAW_NEEDED = c.APP_CMD_WINDOW_REDRAW_NEEDED,
    APP_CMD_CONTENT_RECT_CHANGED = c.APP_CMD_CONTENT_RECT_CHANGED,
    APP_CMD_GAINED_FOCUS = c.APP_CMD_GAINED_FOCUS,
    APP_CMD_LOST_FOCUS = c.APP_CMD_LOST_FOCUS,
    APP_CMD_CONFIG_CHANGED = c.APP_CMD_CONFIG_CHANGED,
    APP_CMD_LOW_MEMORY = c.APP_CMD_LOW_MEMORY,
    APP_CMD_START = c.APP_CMD_START,
    APP_CMD_RESUME = c.APP_CMD_RESUME,
    APP_CMD_SAVE_STATE = c.APP_CMD_SAVE_STATE,
    APP_CMD_PAUSE = c.APP_CMD_PAUSE,
    APP_CMD_STOP = c.APP_CMD_STOP,
    APP_CMD_DESTROY = c.APP_CMD_DESTROY,
};

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

const UserData = struct {
    app: *c.android_app,
    active: bool = false,
    window: ?*c.ANativeWindow = null,

    fn init(app: *c.android_app) @This() {
        return .{
            .app = app,
        };
    }
};

fn handleCmd(app: [*c]c.android_app, _cmd: i32) callconv(.C) void {
    const cmd: AppCmd = @enumFromInt(_cmd);
    std.log.debug("handle_cmd: cmd = {s}", .{@tagName(cmd)});

    const userdata: *UserData = @ptrCast(@alignCast(app.*.userData));
    switch (cmd) {
        .APP_CMD_RESUME => {
            userdata.active = true;
        },
        .APP_CMD_INIT_WINDOW => {
            userdata.window = app.*.window;
        },
        .APP_CMD_PAUSE => {
            userdata.active = false;
        },
        .APP_CMD_TERM_WINDOW => {
            userdata.window = null;
        },
        else => {},
    }
}

//
// NativeActivity entory point
//
export fn android_main(app: *c.android_app) callconv(.C) void {
    std.log.info("#### android_main: enter ####", .{});
    var userdata = UserData.init(app);
    app.userData = &userdata;
    app.onAppCmd = &handleCmd;

    while (app.destroyRequested == 0) {
        var source: ?*c.android_poll_source = null;
        // blocking
        const timeout_millis: c_int = -1;
        const result = c.ALooper_pollOnce(timeout_millis, null, null, @ptrCast(&source));
        if (result < 0) {
            continue;
        }

        if (source) |s| {
            c.call_source_process(app, s);
        }
    }
    std.log.info("#### android_main: exit ####", .{});
}

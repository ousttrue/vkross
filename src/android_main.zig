const std = @import("std");
const c = @import("c_android.zig");

export fn android_main(state: *c.android_app) callconv(.C) void {
    _ = state;
    std.log.info("#### android_main ####", .{});
}

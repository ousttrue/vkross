const std = @import("std");
const build_glfw = @import("build_glfw.zig");

const appname = "vkross";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    std.log.debug("host: {s}", .{b.graph.host.result.zigTriple(b.allocator) catch @panic("OOP")});
    std.log.debug("target: {s}", .{target.result.zigTriple(b.allocator) catch @panic("OOP")});

    // desktop glfw
    const exe = b.addExecutable(.{
        .name = appname,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/main.zig"),
    });
    build_glfw.link(b, target, exe);

    const vkross_dep = b.dependency("vkross", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vkross", vkross_dep.module("vkross"));

    const constants = b.addWriteFile(
        b.path("src/constants.generated.zig").getPath(b),
        b.fmt("pub const appname=\"{s}\";\n", .{appname}),
    );
    exe.step.dependOn(&constants.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    b.installArtifact(exe);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    std.log.debug("host: {s}", .{b.graph.host.result.zigTriple(b.allocator) catch @panic("OOP")});
    std.log.debug("target: {s}", .{target.result.zigTriple(b.allocator) catch @panic("OOP")});

    const root_module = b.addModule("vkross", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/vkross.zig"),
    });

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    root_module.addImport("vulkan", vulkan);
}

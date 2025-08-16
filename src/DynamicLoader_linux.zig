// https://github.com/KhronosGroup/Vulkan-Hpp/blob/main/snippets/DynamicLoader.hpp
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("dlfcn.h");
});

const library_name = "libvulkan.so";
// const library_name = "libvulkan.so.1";

const Opts = struct {
    library_name: []const u8 = library_name,
};

library: *anyopaque,

pub fn init(opts: Opts) @This() {
    return .{ .library = c.dlopen(@ptrCast(opts.library_name), c.RTLD_NOW | c.RTLD_LOCAL).? };
}

pub fn deinit(self: *@This()) void {
    c.dlclose(self.library);
}

pub fn getProcAddress(self: @This(), function: [*:0]const u8) ?*anyopaque {
    return c.dlsym(self.library, function);
}

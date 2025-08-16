// https://github.com/KhronosGroup/Vulkan-Hpp/blob/main/snippets/DynamicLoader.hpp
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", {});
    @cInclude("Windows.h");
});

const library_name = "vulkan-1.dll";

const Opts = struct {
    library_name: []const u8 = library_name,
};

library: c.HINSTANCE,

pub fn init(opts: Opts) @This() {
    return .{ .library = c.LoadLibraryA(@ptrCast(opts.library_name)) };
}

pub fn deinit(self: *@This()) void {
    c.FreeLibrary(self.library);
}

pub fn getProcAddress(self: @This(), function: [*:0]const u8) ?*const fn (...) callconv(.c) c_longlong {
    return c.GetProcAddress(self.library, function);
}

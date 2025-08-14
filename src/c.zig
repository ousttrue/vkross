pub usingnamespace @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
    @cDefine("WIN32_LEAN_AND_MEAN", {});
    @cInclude("Windows.h");
});

const vk = @import("vulkan");

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

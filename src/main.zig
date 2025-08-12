const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const c = @import("c.zig");

const app_name = "vulkancross";

const validation_layers: []const [*:0]const u8 = if (builtin.mode == std.builtin.OptimizeMode.Debug) blk: {
    break :blk &.{
        "VK_LAYER_KHRONOS_validation",
    };
} else blk: {
    break :blk &.{};
};

const instance_extensions: []const [*:0]const u8 = if (builtin.mode == std.builtin.OptimizeMode.Debug)
blk: {
    break :blk &.{
        vk.extensions.ext_debug_utils.name,
    };
} else blk: {
    break :blk &.{};
};

const BaseInStructure = vk.BaseWrapperWithCustomDispatch(vk.BaseDispatch);

fn checkValidationLayerSupport(
    allocator: std.mem.Allocator,
    vkb: *const BaseInStructure,
    validationLayers: []const [*:0]const u8,
) !bool {
    var layer_count: u32 = undefined;
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, null);
    std.log.debug("{} layers", .{layer_count});

    const availableLayers = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(availableLayers);

    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, @ptrCast(availableLayers));

    for (validationLayers) |layer_name| {
        var layerFound = false;
        for (availableLayers) |layer_properties| {
            if (std.mem.eql(
                u8,
                std.mem.sliceTo(layer_name, 0),
                std.mem.sliceTo(&layer_properties.layer_name, 0),
            )) {
                layerFound = true;
                break;
            }
        }
        if (!layerFound) {
            std.log.err("{s} not supported", .{layer_name});
            return false;
        }
    }

    return true;
}

fn debugCallback(
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageType: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    _ = messageSeverity;
    _ = messageType;
    _ = pUserData;
    std.log.debug("[validation layer] {?s}", .{pCallbackData.?.p_message});
    return vk.FALSE;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        @intCast(extent.width),
        @intCast(extent.height),
        app_name,
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfwDestroyWindow(window);

    //
    // init vulkan
    //
    const vkb = vk.BaseWrapper.load(c.glfwGetInstanceProcAddress);

    if (!try checkValidationLayerSupport(allocator, &vkb, validation_layers)) {
        return error.CheckValidationLayer;
    }

    // prepare extensions
    var glfw_exts_count: u32 = undefined;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

    const all_instance_extensions = try allocator.alloc([*:0]const u8, instance_extensions.len + glfw_exts_count);
    defer allocator.free(all_instance_extensions);
    for (instance_extensions, 0..) |instance_extension, i| {
        all_instance_extensions[i] = instance_extension;
    }
    var i = instance_extensions.len;
    for (0..glfw_exts_count) |j| {
        all_instance_extensions[i] = glfw_exts[j];
        i += 1;
    }

    // VkInstance
    const debug_utils_messenger_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .message_severity = .{
            .verbose_bit_ext = true,
            .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .pfn_user_callback = &debugCallback,
    };

    const app_info = vk.ApplicationInfo{
        .p_application_name = app_name,
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .p_engine_name = app_name,
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .api_version = @bitCast(vk.API_VERSION_1_2),
    };
    for (validation_layers) |name| {
        std.log.debug("layer: {s}", .{name});
    }
    for (all_instance_extensions) |name| {
        std.log.debug("instance_extension: {s}", .{name});
    }
    const vk_instance = try vkb.createInstance(&.{
        .p_next = &debug_utils_messenger_create_info,
        .p_application_info = &app_info,
        // layers
        .enabled_layer_count = validation_layers.len,
        .pp_enabled_layer_names = @ptrCast(validation_layers),
        // extensions
        .enabled_extension_count = @intCast(all_instance_extensions.len),
        .pp_enabled_extension_names = @ptrCast(all_instance_extensions),
    }, null);

    const vki = vk.InstanceWrapper.load(vk_instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    const p_instance = vk.InstanceProxy.init(vk_instance, &vki);
    errdefer p_instance.destroyInstance(null);

    const debug_utils_messenger = try p_instance.createDebugUtilsMessengerEXT(&debug_utils_messenger_create_info, null);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        var w: c_int = undefined;
        var h: c_int = undefined;
        c.glfwGetFramebufferSize(window, &w, &h);

        // Don't present or resize swapchain while the window is minimized
        if (w != 0 and h != 0) {}
    }

    p_instance.destroyDebugUtilsMessengerEXT(debug_utils_messenger, null);
    p_instance.destroyInstance(null);
}

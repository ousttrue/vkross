const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

fn debugCallback(
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageType: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    _ = messageType;
    _ = pUserData;
    if (messageSeverity.error_bit_ext) {
        std.log.err("{?s}", .{pCallbackData.?.p_message});
    } else if (messageSeverity.warning_bit_ext) {
        std.log.warn("{?s}", .{pCallbackData.?.p_message});
    } else if (messageSeverity.info_bit_ext) {
        std.log.info("{?s}", .{pCallbackData.?.p_message});
    } else {
        std.log.debug("{?s}", .{pCallbackData.?.p_message});
    }
    return vk.FALSE;
}

allocator: std.mem.Allocator,
vkb: vk.BaseWrapper,
vki: *vk.InstanceWrapper,
vkp_instance: vk.InstanceProxy = undefined,
debug_utils_messenger: vk.DebugUtilsMessengerEXT,

pub const InitOptions = struct {
    app_name: [:0]const u8 = "vulkancross",
    is_debug: bool,
    instance_extensions: []const [*:0]const u8 = &.{},
};

pub fn init(
    allocator: std.mem.Allocator,
    loader: anytype,
    opts: InitOptions,
) !@This() {
    const vkb = vk.BaseWrapper.load(loader);

    const layers: []const [*:0]const u8 = if (opts.is_debug) blk: {
        break :blk &.{
            "VK_LAYER_KHRONOS_validation",
        };
    } else blk: {
        break :blk &.{};
    };
    try checkValidationLayerSupport(allocator, &vkb, layers);

    const debug_extensions: []const [*:0]const u8 = if (opts.is_debug) blk: {
        break :blk &.{
            vk.extensions.ext_debug_utils.name,
        };
    } else blk: {
        break :blk &.{};
    };

    const all_instance_extensions = try std.mem.concat(
        allocator,
        [*:0]const u8,
        &.{ opts.instance_extensions, debug_extensions },
    );
    defer allocator.free(all_instance_extensions);

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
        .p_application_name = opts.app_name,
        .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .p_engine_name = opts.app_name,
        .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
        .api_version = @bitCast(vk.API_VERSION_1_2),
    };
    for (layers) |name| {
        std.log.debug("layer: {s}", .{name});
    }
    for (all_instance_extensions) |name| {
        std.log.debug("instance_extension: {s}", .{name});
    }
    const vk_instance = try vkb.createInstance(&.{
        .p_next = &debug_utils_messenger_create_info,
        .p_application_info = &app_info,
        // layers
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = @ptrCast(layers),
        // extensions
        .enabled_extension_count = @intCast(all_instance_extensions.len),
        .pp_enabled_extension_names = @ptrCast(all_instance_extensions),
    }, null);

    const vki = try allocator.create(vk.InstanceWrapper);
    vki.* = vk.InstanceWrapper.load(vk_instance, vkb.dispatch.vkGetInstanceProcAddr.?);
    const vkp_instance = vk.InstanceProxy.init(vk_instance, vki);

    return .{
        .allocator = allocator,
        .vkb = vkb,
        .vkp_instance = vkp_instance,
        .vki = vki,
        .debug_utils_messenger = try vkp_instance.createDebugUtilsMessengerEXT(
            &debug_utils_messenger_create_info,
            null,
        ),
    };
}

pub fn deinit(self: *@This()) void {
    self.vkp_instance.destroyDebugUtilsMessengerEXT(self.debug_utils_messenger, null);
    self.vkp_instance.destroyInstance(null);
    self.allocator.destroy(self.vki);
}

fn checkValidationLayerSupport(
    allocator: std.mem.Allocator,
    vkb: *const vk.BaseWrapper,
    validationLayers: []const [*:0]const u8,
) !void {
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
            return error.LayerUnsupported;
        }
    }
}

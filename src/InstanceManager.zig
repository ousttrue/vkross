const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const PhysicalDevice = @import("PhysicalDevice.zig");

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

vk_instance: ?vk.Instance = null,
debug_utils_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
physical_devices: []PhysicalDevice = &.{},

pub fn init(
    allocator: std.mem.Allocator,
    loader: anytype,
) @This() {
    const self = @This(){
        .allocator = allocator,
        .vkb = vk.BaseWrapper.load(loader),
        .vki = allocator.create(vk.InstanceWrapper) catch @panic("OOP"),
    };
    return self;
}

pub fn deinit(self: *@This()) void {
    for (self.physical_devices) |physical_device| {
        physical_device.deinit(self.allocator);
    }
    self.allocator.free(self.physical_devices);

    if (self.vk_instance) |vk_instance| {
        self.vki.destroyDebugUtilsMessengerEXT(vk_instance, self.debug_utils_messenger, null);
        self.vki.destroyInstance(vk_instance, null);
    }
    self.allocator.destroy(self.vki);
}

pub const InitOptions = struct {
    app_name: [:0]const u8 = "vulkancross",
    is_debug: bool,
    instance_extensions: []const [*:0]const u8 = &.{},
};

pub fn create(
    self: *@This(),
    opts: InitOptions,
) !vk.InstanceProxy {
    const layers: []const [*:0]const u8 = if (opts.is_debug) blk: {
        break :blk &.{
            "VK_LAYER_KHRONOS_validation",
        };
    } else blk: {
        break :blk &.{};
    };
    try checkValidationLayerSupport(self.allocator, &self.vkb, layers);

    const debug_extensions: []const [*:0]const u8 = if (opts.is_debug) blk: {
        break :blk &.{
            vk.extensions.ext_debug_utils.name,
        };
    } else blk: {
        break :blk &.{};
    };

    const all_instance_extensions = try std.mem.concat(
        self.allocator,
        [*:0]const u8,
        &.{ opts.instance_extensions, debug_extensions },
    );
    defer self.allocator.free(all_instance_extensions);

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
    const vk_instance = try self.vkb.createInstance(&.{
        .p_next = &debug_utils_messenger_create_info,
        .p_application_info = &app_info,
        // layers
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = @ptrCast(layers),
        // extensions
        .enabled_extension_count = @intCast(all_instance_extensions.len),
        .pp_enabled_extension_names = @ptrCast(all_instance_extensions),
    }, null);
    self.vk_instance = vk_instance;

    self.vki.* = vk.InstanceWrapper.load(vk_instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
    self.debug_utils_messenger = try self.vki.createDebugUtilsMessengerEXT(
        vk_instance,
        &debug_utils_messenger_create_info,
        null,
    );

    const proxy = vk.InstanceProxy.init(vk_instance, self.vki);

    const physical_devices = try self.vki.enumeratePhysicalDevicesAlloc(vk_instance, self.allocator);
    defer self.allocator.free(physical_devices);
    self.physical_devices = try self.allocator.alloc(PhysicalDevice, physical_devices.len);
    for (physical_devices, 0..) |physical_device, i| {
        self.physical_devices[i] = try PhysicalDevice.init(self.allocator, &proxy, physical_device);
    }

    return proxy;
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

const PhysicalDeviceAndPresentQueue = struct {
    physical_device: *const PhysicalDevice,
    graphics_queue_family_index: u32,
    present_queue_family_index: u32,
};

pub fn pickPhysicalDevice(
    self: @This(),
    instance: *const vk.InstanceProxy,
    surface: vk.SurfaceKHR,
) !?PhysicalDeviceAndPresentQueue {
    var picked: ?*const PhysicalDevice = null;
    var picked_queue_family_index: ?u32 = null;

    for (self.physical_devices) |*physical_device| {
        try physical_device.debugPrint(instance, surface);
        if (try physical_device.getFirstPresentQueueFamily(instance, surface)) |present_queue_family_index| {
            if (picked == null) {
                // use 1st
                picked = physical_device;
                picked_queue_family_index = present_queue_family_index;
            }
        }
    }
    if (picked) |p| {
        if (picked_queue_family_index) |q| {
            return .{
                .physical_device = p,
                .graphics_queue_family_index = p.select_graphics_family_index() orelse @panic("NoGraphicsQueue"),
                .present_queue_family_index = q,
            };
        }
    }
    if (self.physical_devices.len > 0) {
        // fall back. use 1st device
        const p = &self.physical_devices[0];
        return .{
            .physical_device = p,
            .graphics_queue_family_index = p.select_graphics_family_index() orelse @panic("NoGraphicsQueue"),
            .present_queue_family_index = 0,
        };
    }
    return null;
}

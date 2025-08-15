const std = @import("std");
const vk = @import("vulkan");

physical_device: vk.PhysicalDevice,
device_extensions: []vk.ExtensionProperties,
properties: vk.PhysicalDeviceProperties,
features: vk.PhysicalDeviceFeatures,
queue_family_properties: []vk.QueueFamilyProperties,
memory_properties: vk.PhysicalDeviceMemoryProperties,

pub fn init(
    allocator: std.mem.Allocator,
    instance: *const vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
) !@This() {
    const device_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(
        physical_device,
        null,
        allocator,
    );

    const props = instance.getPhysicalDeviceProperties(physical_device);
    const features = instance.getPhysicalDeviceFeatures(physical_device);
    const queue_family_properties = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
        physical_device,
        allocator,
    );
    const memory_properties = instance.getPhysicalDeviceMemoryProperties(physical_device);

    return .{
        .physical_device = physical_device,
        .device_extensions = device_extensions,
        .properties = props,
        .features = features,
        .queue_family_properties = queue_family_properties,
        .memory_properties = memory_properties,
    };
}

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    allocator.free(self.queue_family_properties);
    allocator.free(self.device_extensions);
}

pub fn select_graphics_family_index(self: @This()) ?u32 {
    for (self.queue_family_properties, 0..) |props, i| {
        if (props.queue_flags.graphics_bit) {
            return @as(u32, @intCast(i));
        }
    }
    return null;
}

pub fn is_device_extension_available(self: @This(), extension: []const u8) bool {
    for (self.device_extension_properties) |props| {
        if (std.mem.eql(props.extension_name, extension)) {
            return true;
        }
    }
    return false;
}

pub fn getFirstPresentQueueFamily(self: @This(), instance: *const vk.InstanceProxy, surface: vk.SurfaceKHR) !?u32 {
    for (0..self.queue_family_properties.len) |i| {
        const available = try instance.getPhysicalDeviceSurfaceSupportKHR(
            self.physical_device,
            @intCast(i),
            surface,
        );
        if (available == vk.TRUE) {
            return @as(u32, @intCast(i));
        }
    }
    return null;
}

pub fn debugPrint(self: @This(), instance: *const vk.InstanceProxy, surface: vk.SurfaceKHR) !void {
    std.log.debug("[{s}] {s}", .{
        std.mem.sliceTo(&self.properties.device_name, 0),
        @tagName(self.properties.device_type),
    });
    std.log.debug("  queue family capabilities: 1:present,2:graphics,3:compute,4:transfer,", .{});
    std.log.debug("    5:sparse,6:protected,7:video_decode,8:video_encode,9:optical", .{});
    std.log.debug("  [  ] 123456789", .{});
    for (self.queue_family_properties, 0..) |prop, i| {
        const presentSupport = try instance.getPhysicalDeviceSurfaceSupportKHR(
            self.physical_device,
            @intCast(i),
            surface,
        );
        std.log.debug("  [{d:02}] {s}{s}{s}{s}{s}{s}{s}{s}{s}", .{
            i,
            if (presentSupport == vk.TRUE) "o" else "_",
            // queueFlagBitsStr(prop.queueFlags, "o", "_") .c_str(),
            if (prop.queue_flags.graphics_bit) "o" else "_",
            if (prop.queue_flags.compute_bit) "o" else "_",
            if (prop.queue_flags.transfer_bit) "o" else "_",
            if (prop.queue_flags.sparse_binding_bit) "o" else "_",
            if (prop.queue_flags.protected_bit) "o" else "_",
            if (prop.queue_flags.video_decode_bit_khr) "o" else "_",
            if (prop.queue_flags.video_encode_bit_khr) "o" else "_",
            if (prop.queue_flags.optical_flow_bit_nv) "o" else "_",
        });
    }
}

//   static std::string queueFlagBitsStr(VkQueueFlags f, const char *enable,
//                                       const char *disable) {
//     std::string str;
//     str += f & VK_QUEUE_GRAPHICS_BIT ? enable : disable;
//     str += f & VK_QUEUE_COMPUTE_BIT ? enable : disable;
//     str += f & VK_QUEUE_TRANSFER_BIT ? enable : disable;
//     str += f & VK_QUEUE_SPARSE_BINDING_BIT ? enable : disable;
//     str += f & VK_QUEUE_PROTECTED_BIT ? enable : disable;
//     str += f & VK_QUEUE_VIDEO_DECODE_BIT_KHR ? enable : disable;
//     str += f & VK_QUEUE_VIDEO_ENCODE_BIT_KHR ? enable : disable;
//     str += f & VK_QUEUE_OPTICAL_FLOW_BIT_NV ? enable : disable;
//     return str;
//   }

//   struct SizeAndTypeIndex {
//     VkDeviceSize requiredSize;
//     uint32_t memoryTypeIndex;
//   };

//   SizeAndTypeIndex
//   findMemoryTypeIndex(VkDevice device,
//                       const VkMemoryRequirements &memoryRequirements,
//                       uint32_t hostRequirements) const {
//     for (uint32_t i = 0; i < VK_MAX_MEMORY_TYPES; i++) {
//       if (memoryRequirements.memoryTypeBits & (1u << i)) {
//         if ((this->memoryProps.memoryTypes[i].propertyFlags &
//              hostRequirements)) {
//           return {
//               .requiredSize = memoryRequirements.size,
//               .memoryTypeIndex = i,
//           };
//         }
//       }
//     }
//     vuloxr::Logger::Error("Failed to obtain suitable memory type.\n");
//     abort();
//   }

//   Memory allocForMap(VkDevice device, VkBuffer buffer) const {
//     // alloc
//     VkMemoryRequirements memoryRequirements;
//     vkGetBufferMemoryRequirements(device, buffer, &memoryRequirements);
//     auto [requiredSize, typeIndex] =
//         this->findMemoryTypeIndex(device, memoryRequirements,
//                                   // for map
//                                   VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
//                                       VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
//     auto memory = createBindMemory(device, requiredSize, typeIndex);
//     // bind
//     vkBindBufferMemory(device, buffer, memory, 0);
//     return {device, memory};
//   }

//   Memory allocForTransfer(VkDevice device, VkBuffer buffer) const {
//     // alloc
//     VkMemoryRequirements memoryRequirements;
//     vkGetBufferMemoryRequirements(device, buffer, &memoryRequirements);
//     auto [requiredSize, typeIndex] =
//         this->findMemoryTypeIndex(device, memoryRequirements,
//                                   // for map
//                                   VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
//     auto memory = createBindMemory(device, requiredSize, typeIndex);
//     // bind
//     vkBindBufferMemory(device, buffer, memory, 0);
//     return {device, memory};
//   }

//   Memory allocForTransfer(VkDevice device, VkImage image) const {
//     // alloc
//     VkMemoryRequirements memoryRequirements;
//     vkGetImageMemoryRequirements(device, image, &memoryRequirements);
//     auto [requiredSize, typeIndex] =
//         this->findMemoryTypeIndex(device, memoryRequirements,
//                                   // for copy command
//                                   VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
//     auto memory = createBindMemory(device, requiredSize, typeIndex);
//     // bind
//     vkBindImageMemory(device, image, memory, 0);
//     return {device, memory};
//   }

//   VkFormat depthFormat() const {
//     /* allow custom depth formats */
// #ifdef __ANDROID__
//     // Depth format needs to be VK_FORMAT_D24_UNORM_S8_UINT on
//     // Android (if available).
//     VkFormatProperties props;
//     vkGetPhysicalDeviceFormatProperties(this->physicalDevice,
//                                         VK_FORMAT_D24_UNORM_S8_UINT, &props);
//     if ((props.linearTilingFeatures &
//          VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) ||
//         (props.optimalTilingFeatures &
//          VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT))
//       return VK_FORMAT_D24_UNORM_S8_UINT;
//     else
//       return VK_FORMAT_D16_UNORM;
// #elif defined(VK_USE_PLATFORM_IOS_MVK)
//     return VK_FORMAT_D32_SFLOAT;
// #else
//     return VK_FORMAT_D16_UNORM;
// #endif
//   }

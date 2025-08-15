const std = @import("std");
const vk = @import("vulkan");

allocator: std.mem.Allocator,
device: *const vk.DeviceProxy,
swapchain: vk.SwapchainKHR,
images: []vk.Image,
present_queue: vk.Queue,

pub fn chooseSwapSurfaceFormat(
    allocator: std.mem.Allocator,
    instance: *const vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !vk.SurfaceFormatKHR {
    const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(formats);
    if (formats.len == 0) {
        return error.NoFormats;
    }
    const requestSurfaceImageFormat = [_]vk.Format{
        // Favor UNORM formats as the samples are not written for sRGB
        .b8g8r8a8_unorm, .r8g8b8a8_unorm,
        .b8g8r8_unorm,
        .r8g8b8_unorm,
        // VK_FORMAT_A8B8G8R8_UNORM_PACK32
        // VK_FORMAT_B8G8R8A8_SRGB,
    };
    for (formats) |availableFormat| {
        if (availableFormat.color_space == .srgb_nonlinear_khr) {
            for (requestSurfaceImageFormat) |format| {
                if (availableFormat.format == format) {
                    return availableFormat;
                }
            }
        }
    }
    return formats[0];
}

pub fn init(
    allocator: std.mem.Allocator,
    vkp_instance: *const vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    queue_family_index: u32,
    present_queue_family_index: u32,
    physical_device: vk.PhysicalDevice,
    device: *const vk.DeviceProxy,
    format: vk.SurfaceFormatKHR,
    composite_alpha: vk.CompositeAlphaFlagsKHR,
) !@This() {
    const surface_capabilities = try vkp_instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        physical_device,
        surface,
    );

    const qfi = [_]u32{
        queue_family_index,
        present_queue_family_index,
    };

    const sharing_mode: vk.SharingMode = if (queue_family_index != present_queue_family_index)
        .concurrent
    else
        .exclusive;

    const swapchain = try device.createSwapchainKHR(&.{
        .surface = surface,
        .min_image_count = surface_capabilities.min_image_count,
        .image_format = format.format,
        .image_color_space = format.color_space,
        .image_extent = surface_capabilities.current_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = qfi.len,
        .p_queue_family_indices = &qfi,
        .pre_transform = surface_capabilities.current_transform,
        .composite_alpha = composite_alpha,
        .present_mode = .fifo_khr,
        .clipped = vk.TRUE,
    }, null);

    var image_count: u32 = undefined;
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, null);
    if (image_count == 0) {
        @panic("no swapchain image");
    }
    std.log.info("swapchain image: {}", .{image_count});

    const images = try allocator.alloc(vk.Image, image_count);
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, @ptrCast(images));

    return .{
        .allocator = allocator,
        .device = device,
        .swapchain = swapchain,
        .images = images,
        .present_queue = device.getDeviceQueue(present_queue_family_index, 0),
    };
}

pub fn deinit(self: @This()) void {
    self.allocator.free(self.images);
    self.device.destroySwapchainKHR(self.swapchain, null);
}

pub const AcquiredImage = struct {
    result: vk.Result,
    present_time: std.time.Instant = undefined,
    image_index: u32 = 0,
    image: vk.Image = .null_handle,
};

pub fn acquireNextImage(
    self: *@This(),
    image_available_semaphore: vk.Semaphore,
) !AcquiredImage {
    // uint32_t imageIndex;
    const acquired = try self.device.acquireNextImageKHR(
        self.swapchain,
        std.math.maxInt(u64),
        image_available_semaphore,
        .null_handle,
    );
    if (acquired.result != .success) {
        return .{
            .result = acquired.result,
        };
    }

    return .{
        .result = acquired.result,
        .present_time = try std.time.Instant.now(),
        .image_index = acquired.image_index,
        .image = self.images[acquired.image_index],
    };
}

pub fn present(self: @This(), imageIndex: u32, semaphores: []vk.Semaphore) !vk.Result {
    return self.device.queuePresentKHR(self.present_queue, &.{
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&self.swapchain),
        .p_image_indices = @ptrCast(&imageIndex),
        .wait_semaphore_count = @intCast(semaphores.len),
        .p_wait_semaphores = @ptrCast(semaphores),
    });
}

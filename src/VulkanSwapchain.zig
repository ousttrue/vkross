const std = @import("std");
const vk = @import("vulkan");

allocator: std.mem.Allocator,
device: vk.Device,
vkd: *const vk.DeviceWrapper,
swapchain: vk.SwapchainKHR,
images: []vk.Image,
present_queue: vk.Queue,

pub fn init(
    allocator: std.mem.Allocator,
    vkp_instance: *vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    queue_family_index: u32,
    present_queue_family_index: u32,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    vkd: *const vk.DeviceWrapper,
) !@This() {
    const surface_capabilities = try vkp_instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
        physical_device,
        surface,
    );

    const preferred = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    const qfi = [_]u32{
        queue_family_index,
        present_queue_family_index,
    };

    const sharing_mode: vk.SharingMode = if (queue_family_index != present_queue_family_index)
        .concurrent
    else
        .exclusive;

    const swapchain = try vkd.createSwapchainKHR(device, &.{
        .surface = surface,
        .min_image_count = surface_capabilities.min_image_count,
        .image_format = preferred.format,
        .image_color_space = preferred.color_space,
        .image_extent = surface_capabilities.current_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = qfi.len,
        .p_queue_family_indices = &qfi,
        .pre_transform = surface_capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = .fifo_khr,
        .clipped = vk.TRUE,
    }, null);

    var image_count: u32 = undefined;
    _ = try vkd.getSwapchainImagesKHR(device, swapchain, &image_count, null);
    if (image_count == 0) {
        @panic("no swapchain image");
    }
    std.log.info("swapchain image: {}", .{image_count});

    const images = try allocator.alloc(vk.Image, image_count);
    _ = try vkd.getSwapchainImagesKHR(device, swapchain, &image_count, @ptrCast(images));

    return .{
        .allocator = allocator,
        .device = device,
        .vkd = vkd,
        .swapchain = swapchain,
        .images = images,
        .present_queue = vkd.getDeviceQueue(device, present_queue_family_index, 0),
    };
}

pub fn deinit(self: @This()) void {
    self.allocator.free(self.images);
    self.vkd.destroySwapchainKHR(self.device, self.swapchain, null);
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
    const acquired = try self.vkd.acquireNextImageKHR(
        self.device,
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
    return self.vkd.queuePresentKHR(self.present_queue, &.{
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&self.swapchain),
        .p_image_indices = @ptrCast(&imageIndex),
        .wait_semaphore_count = @intCast(semaphores.len),
        .p_wait_semaphores = @ptrCast(semaphores),
    });
}

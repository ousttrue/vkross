const std = @import("std");
const vk = @import("vulkan");

swapchain: vk.SwapchainKHR,
images: []vk.Image,

pub fn init(
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
    swapchain: vk.SwapchainKHR,
) !@This() {
    var image_count: u32 = undefined;
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, null);
    if (image_count == 0) {
        @panic("no swapchain image");
    }

    const images = try allocator.alloc(vk.Image, image_count);
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, @ptrCast(images));

    return @This(){
        .swapchain = swapchain,
        .images = images,
    };
}

pub fn deinit(
    self: @This(),
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
) void {
    allocator.free(self.images);
    device.destroySwapchainKHR(self.swapchain, null);
}

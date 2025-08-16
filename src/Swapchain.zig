const std = @import("std");
const vk = @import("vulkan");
const FlightManager = @import("FlightManager.zig");

swapchain: vk.SwapchainKHR,
images: []vk.Image,
flight_manager: FlightManager,

pub fn init(
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
    swapchain: vk.SwapchainKHR,
    graphics_queue_family_index: u32,
) !@This() {
    var image_count: u32 = undefined;
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, null);
    if (image_count == 0) {
        @panic("no swapchain image");
    }

    const images = try allocator.alloc(vk.Image, image_count);
    _ = try device.getSwapchainImagesKHR(swapchain, &image_count, @ptrCast(images));

    const flight_manager = try FlightManager.init(
        allocator,
        device,
        graphics_queue_family_index,
        image_count,
    );

    return @This(){
        .swapchain = swapchain,
        .images = images,
        .flight_manager = flight_manager,
    };
}

pub fn deinit(
    self: @This(),
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
) void {
    self.flight_manager.deinit();
    allocator.free(self.images);
    device.destroySwapchainKHR(self.swapchain, null);
}

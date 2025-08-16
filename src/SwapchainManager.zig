const std = @import("std");
const vk = @import("vulkan");
const Swapchain = @import("Swapchain.zig");

allocator: std.mem.Allocator,
instance: *const vk.InstanceProxy,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
device: *const vk.DeviceProxy,
present_queue: vk.Queue,
qfi: [2]u32,
create_info: vk.SwapchainCreateInfoKHR,
current: ?Swapchain = null,

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
    instance: *const vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    queue_family_index: u32,
    present_queue_family_index: u32,
    device: *const vk.DeviceProxy,
    format: vk.SurfaceFormatKHR,
    composite_alpha: vk.CompositeAlphaFlagsKHR,
) !@This() {
    const sharing_mode: vk.SharingMode = if (queue_family_index != present_queue_family_index)
        .concurrent
    else
        .exclusive;

    return .{
        .allocator = allocator,
        .instance = instance,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .present_queue = device.getDeviceQueue(present_queue_family_index, 0),
        .qfi = [2]u32{
            queue_family_index,
            present_queue_family_index,
        },
        .create_info = .{
            .surface = undefined,
            .min_image_count = undefined,
            .image_extent = undefined,
            .pre_transform = undefined,
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = sharing_mode,
            .composite_alpha = composite_alpha,
            .present_mode = .fifo_khr,
            .clipped = vk.TRUE,
        },
    };
}

pub fn deinit(self: @This()) void {
    if (self.current) |current| {
        current.deinit(self.allocator, self.device);
    }
}

pub const AcquiredImage = struct {
    result: vk.Result,
    present_time: std.time.Instant = undefined,
    image_index: u32 = 0,
    image: vk.Image = .null_handle,
};

pub fn acquireNextImageOrCreate(
    self: *@This(),
    image_available_semaphore: vk.Semaphore,
    extent: vk.Extent2D,
) !?AcquiredImage {
    if (self.current) |current| {
        // uint32_t imageIndex;
        const acquired = try self.device.acquireNextImageKHR(
            current.swapchain,
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
            .image = current.images[acquired.image_index],
        };
    } else {
        const surface_capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            self.physical_device,
            self.surface,
        );

        self.create_info.surface = self.surface;
        self.create_info.min_image_count = surface_capabilities.min_image_count;
        self.create_info.queue_family_index_count = self.qfi.len;
        self.create_info.p_queue_family_indices = &self.qfi;
        self.create_info.pre_transform = surface_capabilities.current_transform;

        if (surface_capabilities.current_extent.width == 0xFFFFFFFF) {
            self.create_info.image_extent = extent;
        } else {
            self.create_info.image_extent = surface_capabilities.current_extent;
        }

        const swapchain = try self.device.createSwapchainKHR(&self.create_info, null);

        const current = try Swapchain.init(self.allocator, self.device, swapchain);
        std.log.info("swapchain created {} x {}. {} images", .{
            self.create_info.image_extent.width,
            self.create_info.image_extent.height,
            current.images.len,
        });
        self.current = current;

        if (self.create_info.old_swapchain != .null_handle) {
            self.device.destroySwapchainKHR(self.create_info.old_swapchain, null);
            self.create_info.old_swapchain = .null_handle;
        }

        return null;
    }
}

pub fn present(self: *@This(), imageIndex: u32, semaphores: []vk.Semaphore) !void {
    const current = self.current orelse return error.NoCurrentSwapchain;
    if (self.device.queuePresentKHR(self.present_queue, &.{
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&current.swapchain),
        .p_image_indices = @ptrCast(&imageIndex),
        .wait_semaphore_count = @intCast(semaphores.len),
        .p_wait_semaphores = @ptrCast(semaphores),
    })) |res| {
        switch (res) {
            .success => {},
            .suboptimal_khr => {
                // clear current
                self.create_info.old_swapchain = current.swapchain;
                self.allocator.free(current.images);
                self.current = null;
            },
            else => {
                std.log.err("queuePresentKHR: {s}", .{@tagName(res)});
                @panic("queuePresentKHR");
            },
        }
    } else |err| {
        switch (err) {
            error.OutOfDateKHR => {
                // clear current
                self.create_info.old_swapchain = current.swapchain;
                self.allocator.free(current.images);
                self.current = null;
            },
            else => {
                std.log.err("queuePresentKHR: {s}", .{@errorName(err)});
                @panic("queuePresentKHR");
            },
        }
    }
}

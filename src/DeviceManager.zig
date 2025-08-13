const std = @import("std");
const vk = @import("vulkan");

allocator: std.mem.Allocator,
vkd: *vk.DeviceWrapper,
vk_device: ?vk.Device = null,

pub fn init(
    allocator: std.mem.Allocator,
) @This() {
    return .{
        .allocator = allocator,
        .vkd = allocator.create(vk.DeviceWrapper) catch @panic("OOP"),
    };
}

pub fn deinit(self: *@This()) void {
    if (self.vk_device) |vk_device| {
        self.vkd.destroyDevice(vk_device, null);
    }
    self.allocator.destroy(self.vkd);
}

pub fn create(
    self: *@This(),
    vki: *const vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    queue_family_index: u32,
    present_queue_family_index: u32,
    device_extensions: []const [*:0]const u8,
) !vk.DeviceProxy {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = queue_family_index,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = present_queue_family_index,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };
    const queue_count: u32 = if (queue_family_index == present_queue_family_index)
        1
    else
        2;

    for (device_extensions) |name| {
        std.log.debug("device extension: {s}", .{name});
    }
    const vk_device = try vki.createDevice(physical_device, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = @ptrCast(device_extensions),
    }, null);
    self.vk_device = vk_device;
    self.vkd.* = vk.DeviceWrapper.load(vk_device, vki.wrapper.dispatch.vkGetDeviceProcAddr.?);

    return vk.DeviceProxy.init(vk_device, self.vkd);
}

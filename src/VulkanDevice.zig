const std = @import("std");
const vk = @import("vulkan");

allocator: std.mem.Allocator,
vki: *const vk.InstanceProxy,
device: vk.Device,
vkd: *const vk.DeviceWrapper,

pub fn init(
    allocator: std.mem.Allocator,
    vki: *const vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    queue_family_index: u32,
    present_queue_family_index: u32,
    device_extensions: []const [*:0]const u8,
) !@This() {
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
    const device = try vki.createDevice(physical_device, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = @ptrCast(device_extensions),
    }, null);
    const vkd = try allocator.create(vk.DeviceWrapper);
    vkd.* = vk.DeviceWrapper.load(device, vki.wrapper.dispatch.vkGetDeviceProcAddr.?);

    return .{
        .allocator = allocator,
        .vki = vki,
        .device = device,
        .vkd = vkd,
    };
}

pub fn deinit(self: *@This()) void {
    self.vkd.destroyDevice(self.device, null);
    self.allocator.destroy(self.vkd);
}

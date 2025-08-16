const std = @import("std");
const vk = @import("vulkan");

const Flight = struct {
    submit_fence: vk.Fence,
    command_buffer: vk.CommandBuffer,

    fn init(
        device: *const vk.DeviceProxy,
        command_buffer: vk.CommandBuffer,
    ) !@This() {
        const submit_fence = try device.createFence(&.{
            // .flags = .{ .signaled_bit = true },
        }, null);
        return @This(){
            .submit_fence = submit_fence,
            .command_buffer = command_buffer,
        };
    }

    fn deinit(
        self: @This(),
        device: *const vk.DeviceProxy,
    ) void {
        device.destroyFence(self.submit_fence, null);
    }
};

allocator: std.mem.Allocator,
device: *const vk.DeviceProxy,
command_pool: vk.CommandPool,
command_buffers: []vk.CommandBuffer,
flights: []Flight,

pub fn init(
    allocator: std.mem.Allocator,
    device: *const vk.DeviceProxy,
    queue_family_index: u32,
    image_count: usize,
) !@This() {
    std.log.debug("FlightManager: {}", .{image_count});
    const command_pool = try device.createCommandPool(&.{
        .queue_family_index = queue_family_index,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);

    const command_buffers = try allocator.alloc(vk.CommandBuffer, image_count);
    try device.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = @intCast(command_buffers.len),
    }, @ptrCast(command_buffers));

    var flights = try allocator.alloc(Flight, image_count);
    for (0..flights.len) |i| {
        flights[i] = try Flight.init(device, command_buffers[i]);
    }

    return @This(){
        .allocator = allocator,
        .device = device,
        .command_pool = command_pool,
        .command_buffers = command_buffers,
        .flights = flights,
    };
}

pub fn deinit(
    self: @This(),
) void {
    for (self.flights) |flight| {
        flight.deinit(self.device);
    }
    self.allocator.free(self.flights);

    // self.device.freeCommandBuffers(
    //     self.command_pool,
    //     @intCast(self.command_buffers.len),
    //     @ptrCast(self.command_buffers),
    // );
    self.allocator.free(self.command_buffers);
    self.device.destroyCommandPool(self.command_pool, null);
}

const std = @import("std");
const vk = @import("vulkan");

fn colorForTime(now: i128) [4]f32 {
    const elapsed1 = @as(f64, @floatFromInt(now)) / std.time.ns_per_s;

    return .{
        0,
        @floatCast((std.math.sin(elapsed1 * std.math.pi) + 1) * 0.5),
        0,
        1,
    };
}

pub fn recordClearImage(
    device: *const vk.DeviceProxy,
    cb: vk.CommandBuffer,
    image: vk.Image,
    nano_timestamp: i128,
) !void {
    const sub = vk.ImageSubresourceRange{
        .aspect_mask = .{ .color_bit = true },
        .layer_count = 1,
        .base_array_layer = 0,
        .level_count = 1,
        .base_mip_level = 0,
    };

    // record commandbuffer
    try device.beginCommandBuffer(cb, &.{});

    // .undefined => .transfer
    device.cmdPipelineBarrier(cb,
        // src_stage_mask
        .{ .bottom_of_pipe_bit = true },
        // dst_stage_mask
        .{ .top_of_pipe_bit = true }, .{},
        // memory, buffer
        0, null, 0, null,
        // image
        1, &.{.{
            .src_access_mask = .{ .memory_read_bit = true },
            .old_layout = .undefined,
            .dst_access_mask = .{ .memory_write_bit = true },
            .new_layout = .transfer_dst_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = sub,
        }});

    // require.transfer_dst_optimal
    device.cmdClearColorImage(
        cb,
        image,
        .transfer_dst_optimal,
        &.{
            .float_32 = colorForTime(nano_timestamp),
        },
        1,
        @ptrCast(&sub),
    );

    // .transfer_dst_optimal => .present_src_khr
    device.cmdPipelineBarrier(cb,
        // src_stage_mask
        .{ .bottom_of_pipe_bit = true },
        // dst_stage_mask
        .{ .top_of_pipe_bit = true }, .{},
        // memory, buffer
        0, null, 0, null,
        // image
        1, &.{.{
            .src_access_mask = .{ .memory_write_bit = true },
            .old_layout = .transfer_dst_optimal,
            .dst_access_mask = .{ .memory_read_bit = true },
            .new_layout = .present_src_khr, // this is required from VkQueuePresentKHR
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = sub,
        }});

    try device.endCommandBuffer(cb);
}

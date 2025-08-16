const builtin = @import("builtin");

pub const vk = @import("vulkan");
pub const InstanceManager = @import("InstanceManager.zig");
pub const DeviceManager = @import("DeviceManager.zig");
pub const SwapchainManager = @import("SwapchainManager.zig");
pub const renderer = @import("renderer.zig");
pub const DynamicLoader = if (builtin.target.os.tag == .windows)
    @import("DynamicLoader_win32.zig")
else
    @import("DynamicLoader_linux.zig");

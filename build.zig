const std = @import("std");
const build_glfw = @import("build_glfw.zig");
const android = @import("android");

const name = "vkross";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    std.log.debug("{s}", .{target.result.zigTriple(b.allocator) catch @panic("OOP")});

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    if (target.result.abi.isAndroid()) {
        // android native activity
        // ex. zig build -Dtarget=aarch64-linux-android
        const exe = b.addSharedLibrary(.{
            .name = name,
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/android_main.zig"),
            .link_libc = true,
        });
        exe.root_module.addImport("vulkan", vulkan);

        const android_dep = b.dependency("android", .{
            .optimize = optimize,
            .target = target,
        });
        exe.root_module.addImport("android", android_dep.module("android"));

        // build {name}.apk
        const android_sdk = android.Sdk.create(b, .{});
        const apk = android_sdk.createApk(.{
            .api_level = .android15,
            .build_tools_version = "35.0.1",
            .ndk_version = "29.0.13113456",
        });
        const key_store_file = android_sdk.createKeyStore(.example);
        apk.setKeyStore(key_store_file);
        apk.setAndroidManifest(b.path("android/AndroidManifest.xml"));
        apk.addResourceDirectory(b.path("android/res"));

        exe.addIncludePath(.{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{apk.ndk.path}) });
        exe.addCSourceFile(.{
            .file = .{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue/android_native_app_glue.c", .{apk.ndk.path}) },
        });
        // exe.addCSourceFile(.{
        //     .file = b.path("src/helper.cpp"),
        // });
        // exe.target_link_options(${TARGET_NAME} PUBLIC -u ANativeActivity_onCreate)
        const libs = [_][]const u8{
            "android",
            "EGL",
            "GLESv1_CM",
            "log",
        };
        for (libs) |lib| {
            exe.linkSystemLibrary(lib);
        }

        apk.addArtifact(exe);

        const installed_apk = apk.addInstallApk();
        b.getInstallStep().dependOn(&installed_apk.step);

        const run_step = b.step("run", "Install and run the application on an Android device");
        const adb_install = android_sdk.addAdbInstall(installed_apk.source);
        const adb_start = android_sdk.addAdbStart("com.zig.vkross/android.app.NativeActivity");
        adb_start.step.dependOn(&adb_install.step);
        run_step.dependOn(&adb_start.step);

        b.installArtifact(exe);
    } else {
        // desktop glfw
        const exe = b.addExecutable(.{
            .name = name,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/main.zig"),
        });
        build_glfw.link(b, exe);
        exe.root_module.addImport("vulkan", vulkan);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        b.installArtifact(exe);
    }
}

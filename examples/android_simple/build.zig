const std = @import("std");
const android = @import("android");

const pkgname = "simple_native_activity";

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{});
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .android,
    });
    std.log.debug("host: {s}", .{b.graph.host.result.zigTriple(b.allocator) catch @panic("OOP")});
    std.log.debug("target: {s}", .{target.result.zigTriple(b.allocator) catch @panic("OOP")});
    if (!target.result.abi.isAndroid()) {
        @panic("android abi required");
    }
    const optimize = b.standardOptimizeOption(.{});

    // android native activity
    const so = b.addSharedLibrary(.{
        .name = pkgname,
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/android_main.zig"),
        .link_libc = true,
    });
    // zig-out/lib/lib{pkgname}.so
    b.installArtifact(so);

    const android_dep = b.dependency("android", .{
        .optimize = optimize,
        .target = target,
    });
    so.root_module.addImport("android", android_dep.module("android"));

    // build {pkgname}.apk (lib/arm64-v8a/libmain.so rename from lib{pkgname}.so)
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

    // native_app_glue for android_main
    linkNativeAppGlue(b, so, apk.ndk.path);

    // must after all source and lib added.
    apk.addArtifact(so);

    const installed_apk = apk.addInstallApk();
    b.getInstallStep().dependOn(&installed_apk.step);

    const run_step = b.step("run", "Install and run the application on an Android device");
    const adb_install = android_sdk.addAdbInstall(installed_apk.source);
    const adb_start = android_sdk.addAdbStart(b.fmt("com.zig.{s}/android.app.NativeActivity", .{pkgname}));
    adb_start.step.dependOn(&adb_install.step);
    run_step.dependOn(&adb_start.step);
}

fn linkNativeAppGlue(b: *std.Build, so: *std.Build.Step.Compile, ndk_path: []const u8) void {
    so.addIncludePath(.{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{ndk_path}) });
    so.addIncludePath(b.path("src"));
    so.addCSourceFile(.{
        .file = .{ .cwd_relative = b.fmt("{s}/sources/android/native_app_glue/android_native_app_glue.c", .{ndk_path}) },
    });
    so.addCSourceFile(.{
        .file = b.path("src/cpp_helper.cpp"),
    });
    const libs = [_][]const u8{
        "android",
        "log",
    };
    for (libs) |lib| {
        so.linkSystemLibrary(lib);
    }
}

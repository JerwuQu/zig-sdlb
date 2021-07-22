const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    // Working Windows target provided for convenience
    const target = if (b.option(bool, "windows", "Cross-compile to Windows") orelse false)
            std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }
            else b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    // Example runner
    const exe = b.addExecutable("examples", "main.zig");
    const skipAssetMake = b.option(bool, "skip-asset-make", "Don't build assets") orelse false;
    if (!skipAssetMake) {
        const makeAssets = b.addSystemCommand(&.{ "make" });
        exe.step.dependOn(&makeAssets.step);
    }
    exe.setTarget(target);
    exe.setBuildMode(mode);

    // TODO: Move elsewhere
    // vvvvvvv
    exe.addPackagePath("sdlb", "../src/sdlb.zig");
    exe.linkLibC();
    if (target.os_tag != null and target.os_tag.? == .windows) {
        if (target.abi.? != .gnu or target.cpu_arch.? != .x86_64) {
            std.log.err("windows target only supports x86 gnu", .{});
            return error.invalid_target;
        }

        // Windows libs required for SDL2
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("version");
        exe.linkSystemLibrary("setupapi");

        // Static MinGW libs
        exe.addIncludeDir("../mingw64/include");
        exe.addIncludeDir("../mingw64/include/SDL2");
        exe.addIncludeDir("../mingw64/include/opus");
        exe.addObjectFile("../mingw64/lib/libSDL2.a");
        exe.addObjectFile("../mingw64/lib/libzstd.a");
        exe.addObjectFile("../mingw64/lib/libogg.a");
        exe.addObjectFile("../mingw64/lib/libopus.a");
        exe.addObjectFile("../mingw64/lib/libopusfile.a");
    } else {
        exe.addIncludeDir("SDL2");
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("zstd");
        exe.linkSystemLibrary("opusfile");
    }
    // ^^^^^^^

    exe.install();

    const runCmd = exe.run();
    runCmd.step.dependOn(&exe.install_step.?.step);
    if (b.args) |args| {
        runCmd.addArgs(args);
    }
    const runStep = b.step("run", "Run the example runner");
    runStep.dependOn(&runCmd.step);
}

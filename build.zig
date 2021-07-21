const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const winCompile = b.option(bool, "windows", "Cross-compile to Windows") orelse false; // TODO: check for build target rather than setting it
    const target = if (winCompile) std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu } else b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // Example runner
    const exrunner = b.addExecutable("examples", "examples/_examples_.zig");
    const skipAssetMake = b.option(bool, "skip-asset-make", "Don't build example assets") orelse false;
    if (!skipAssetMake) {
        const makeAssets = b.addSystemCommand(&.{ "make", "-C", "examples/assets" });
        exrunner.step.dependOn(&makeAssets.step);
    }
    exrunner.setTarget(target);
    exrunner.setBuildMode(mode);
    exrunner.addPackagePath("sdlb", "src/sdlb.zig");
    exrunner.linkLibC();
    if (winCompile) {
        // Windows libs required for SDL2
        exrunner.linkSystemLibrary("gdi32");
        exrunner.linkSystemLibrary("winmm");
        exrunner.linkSystemLibrary("imm32");
        exrunner.linkSystemLibrary("ole32");
        exrunner.linkSystemLibrary("oleaut32");
        exrunner.linkSystemLibrary("version");
        exrunner.linkSystemLibrary("setupapi");

        // Static MinGW libs
        exrunner.addIncludeDir("mingw64/include");
        exrunner.addIncludeDir("mingw64/include/SDL2");
        exrunner.addIncludeDir("mingw64/include/opus");
        exrunner.addObjectFile("mingw64/lib/libSDL2.a");
        exrunner.addObjectFile("mingw64/lib/libzstd.a");
        exrunner.addObjectFile("mingw64/lib/libogg.a");
        exrunner.addObjectFile("mingw64/lib/libopus.a");
        exrunner.addObjectFile("mingw64/lib/libopusfile.a");
    } else {
        exrunner.addIncludeDir("SDL2");
        exrunner.linkSystemLibrary("SDL2");
        exrunner.linkSystemLibrary("zstd");
        exrunner.linkSystemLibrary("opusfile");
    }
    exrunner.install();

    const run_ex_cmd = exrunner.run();
    run_ex_cmd.step.dependOn(&exrunner.install_step.?.step);
    if (b.args) |args| {
        run_ex_cmd.addArgs(args);
    }
    const run_ex_step = b.step("examples", "Run the example runner");
    run_ex_step.dependOn(&run_ex_cmd.step);
}
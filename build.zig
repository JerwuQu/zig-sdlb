const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const winCompile = b.option(bool, "windows", "Cross-compile to Windows") orelse false;
    const target = if (winCompile) std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu } else b.standardTargetOptions(.{});

    const exOpt = ExOpt{
        .mode = b.standardReleaseOptions(),
        .target = target,
        .winCompile = winCompile,
        .skipAssetMake = b.option(bool, "skip-asset-make", "Don't build assets") orelse false,
    };

    // Example
    buildExample(b, exOpt, "general");
    buildExample(b, exOpt, "bitmap-font");
}

const ExOpt = struct {
    mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    winCompile: bool,
    skipAssetMake: bool,
};

fn buildExample(b: *std.build.Builder, opt: ExOpt, comptime name: []const u8) void {
    const example = b.addExecutable("example-" ++ name, "examples/" ++ name ++ ".zig");
    if (!opt.skipAssetMake) {
        const makeAssets = b.addSystemCommand(&.{ "make", "-C", "examples/assets" });
        example.step.dependOn(&makeAssets.step);
    }
    example.setTarget(opt.target);
    example.setBuildMode(opt.mode);
    example.addPackage(.{ .name = "sdlb", .path = "src/sdlb.zig" });
    example.linkLibC();
    if (opt.winCompile) {
        // Windows libs required for SDL2
        example.linkSystemLibrary("gdi32");
        example.linkSystemLibrary("winmm");
        example.linkSystemLibrary("imm32");
        example.linkSystemLibrary("ole32");
        example.linkSystemLibrary("oleaut32");
        example.linkSystemLibrary("version");
        example.linkSystemLibrary("setupapi");

        // Static MinGW libs
        example.addIncludeDir("mingw64/include");
        example.addIncludeDir("mingw64/include/SDL2");
        example.addIncludeDir("mingw64/include/opus");
        example.addObjectFile("mingw64/lib/libSDL2.a");
        example.addObjectFile("mingw64/lib/libzstd.a");
        example.addObjectFile("mingw64/lib/libogg.a");
        example.addObjectFile("mingw64/lib/libopus.a");
        example.addObjectFile("mingw64/lib/libopusfile.a");
    } else {
        example.addIncludeDir("SDL2");
        example.linkSystemLibrary("SDL2");
        example.linkSystemLibrary("zstd");
        example.linkSystemLibrary("opusfile");
    }
    example.install();

    const run_ex_cmd = example.run();
    run_ex_cmd.step.dependOn(&example.install_step.?.step);
    const run_ex_step = b.step("example-" ++ name, "Run the '" ++ name ++ "' example");
    run_ex_step.dependOn(&run_ex_cmd.step);
}

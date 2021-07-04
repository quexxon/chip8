const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const wasm = b.addSharedLibrary("chip8", "src/chip8/main.zig", .unversioned);
    wasm.setBuildMode(mode);
    wasm.setOutputDir("zig-out");
    wasm.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });

    var main_tests = b.addTest("src/chip8/main.zig");
    main_tests.setBuildMode(mode);

    b.step("test", "Run library tests").dependOn(&main_tests.step);
    b.step("wasm", "Build WASM library").dependOn(&wasm.step);
    b.default_step.dependOn(&wasm.step);
}

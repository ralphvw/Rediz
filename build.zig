const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("Rediz", "src/redis.zig");
    lib.setBuildMode(mode);

    // Add dependencies, if any
    // lib.linkLibrary("dependency");

    // Install the library for local use
    const install_step = b.installArtifact(lib);

    // Add a test step
    const exe = b.addExecutable("redis-zig-test", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkLibrary(lib);
    b.default_step.dependOn(&exe.step);
    install_step.dependOn(&exe.step);
}

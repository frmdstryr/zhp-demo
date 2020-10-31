// This tells the buildpack which version to install
// zig-release: zig-linux-x86_64-0.6.0+9ca981948.tar.xz
//
const std = @import("std");
const Builder = std.build.Builder;


pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("zhttpd", "main.zig");

    exe.setBuildMode(.ReleaseSafe);
    exe.addPackagePath("zhp", "zig-packages/zhp-master/lib/zhp/zhp.zig");
    const run_cmd = exe.run();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}

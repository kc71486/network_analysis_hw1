const std = @import("std");

pub fn build(b: *std.Build) void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // compile and install exe
    const exe = b.addExecutable(.{
        .name = "network_sim",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const install_exe = b.addInstallArtifact(exe, .{});

    // run exe
    const run_exe = b.addRunArtifact(exe);
    run_exe.setCwd(b.path("zig-out/bin"));
    if (b.args) |args| {
        run_exe.addArgs(args);
    }


    // steps & dependencies
    b.getInstallStep().dependOn(&install_exe.step);

    const step_all = b.step("all", "Install and run exe");
    run_exe.step.dependOn(b.getInstallStep());
    step_all.dependOn(&run_exe.step);
}

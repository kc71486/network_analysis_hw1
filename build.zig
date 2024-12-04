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

    // compile test
    const tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // run exe
    const run_exe = b.addRunArtifact(exe);
    // run_exe.setCwd(b.path("zig-out/bin"));
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    // run test
    const run_tests = b.addRunArtifact(tests);

    // steps & dependencies
    b.getInstallStep().dependOn(&install_exe.step);

    const step_test = b.step("test", "Install and run test");
    step_test.dependOn(b.getInstallStep());
    step_test.dependOn(&run_tests.step);

    const step_run = b.step("run", "Install, run test and run exe");
    run_exe.step.dependOn(b.getInstallStep());
    run_exe.step.dependOn(&run_tests.step);
    step_run.dependOn(&run_exe.step);
}

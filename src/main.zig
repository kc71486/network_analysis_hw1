/// Overrides options
pub const std_options = .{
    // Set the log level to warn
    .log_level = .warn,
};

const ArgOptions = struct {
    seed: u64,
    do_plot: bool,
    pyname: []const u8,
};

const SimulatePrintConfig = struct {
    cwd: std.fs.Dir,
    allocator: std.mem.Allocator,
    file_name: []const u8,
    interarrival_time: f64,
    complexity: f64,
    beta_arr: []const usize,
    seed: u64,
    do_plot: bool,
    pyname: []const u8,
};

const SimulationResult = struct {
    discard_ratio: f64,
    storage_server_uptime_ratio: f64,
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator: std.mem.Allocator = gpa.allocator();
    const cwd = std.fs.cwd();

    const arg_option: ArgOptions = try argParse(allocator);
    defer allocator.free(arg_option.pyname);

    try simulatePrint(&.{
        .cwd = cwd,
        .allocator = allocator,
        .file_name = "result1.txt",
        .interarrival_time = 1.0 / 120.0,
        .complexity = 200.0,
        .beta_arr = &.{ 20, 40, 60, 80, 100 },
        .seed = arg_option.seed,
        .do_plot = arg_option.do_plot,
        .pyname = arg_option.pyname,
    });
    try simulatePrint(&.{
        .cwd = cwd,
        .allocator = allocator,
        .file_name = "result2.txt",
        .interarrival_time = 1.0 / 240.0,
        .complexity = 400.0,
        .beta_arr = &.{ 20, 40, 60, 80, 100 },
        .seed = arg_option.seed,
        .do_plot = arg_option.do_plot,
        .pyname = arg_option.pyname,
    });
}

/// Parse system arguments into a struct.
pub fn argParse(allocator: std.mem.Allocator) !ArgOptions {
    // default options
    const defaultpyname: []const u8 = if (builtin.os.tag == .windows) "py" else "python3";
    var arg_option: ArgOptions = .{
        .seed = 1100,
        .do_plot = true,
        .pyname = try allocator.dupe(u8, defaultpyname),
    };

    var arg_iterator: std.process.ArgIterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    _ = arg_iterator.next().?; // program name
    while (arg_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--seed")) {
            arg_option.seed = try std.fmt.parseInt(u64, arg_iterator.next().?, 10);
        } else if (std.mem.eql(u8, arg, "--plot")) {
            arg_option.do_plot = true;
        } else if (std.mem.eql(u8, arg, "--noplot")) {
            arg_option.do_plot = false;
        } else if (std.mem.eql(u8, arg, "--pyname")) {
            allocator.free(arg_option.pyname); // remove old allocation
            arg_option.pyname = try allocator.dupe(u8, arg_iterator.next().?);
        } else {
            std.log.warn("argument ignored: {s}", .{arg});
        }
    }
    return arg_option;
}

/// Simulate and print
pub fn simulatePrint(config: *const SimulatePrintConfig) !void {
    const thread_list: []std.Thread = try config.allocator.alloc(std.Thread, config.beta_arr.len);
    defer config.allocator.free(thread_list);
    const gpa_list: []std.heap.GeneralPurposeAllocator(.{}) = try config.allocator.alloc(std.heap.GeneralPurposeAllocator(.{}), config.beta_arr.len);
    defer config.allocator.free(gpa_list);
    const result_list: []SimulationResult = try config.allocator.alloc(SimulationResult, config.beta_arr.len);
    defer config.allocator.free(result_list);
    // Pass argument to `runOnce`.
    for (config.beta_arr, thread_list, gpa_list, result_list) |beta, *thread, *gpa, *result| {
        gpa.* = std.heap.GeneralPurposeAllocator(.{}).init;
        thread.* = try std.Thread.spawn(.{
            .allocator = config.allocator,
        }, runOnce, .{
            gpa.allocator(), // allocator
            config.interarrival_time, // interarrival_time
            config.complexity, // complexity
            beta, // beta
            config.seed, // seed_base
            result, // out_result
        });
    }
    for (thread_list, gpa_list) |thread, *gpa| {
        thread.join();
        _ = gpa.deinit();
    }
    // Only output result after all threads are finished. Somehow placing in previous
    // causes stdout to be weird (while file writer isn't affected).
    for (config.beta_arr, result_list) |beta, result| {
        std.log.info(
            "interarrival time: {d:.4}, complexity: {d}, beta: {d}",
            .{ config.interarrival_time, config.complexity, beta },
        );
        std.log.info("discard ratio: {d:.3}", .{result.discard_ratio});
        std.log.info("storage uptime ratio: {d:.3}\n", .{result.storage_server_uptime_ratio});
    }
    // Write to result file.
    const cwd = std.fs.cwd();
    var file = try cwd.createFile(config.file_name, .{ .read = false });
    defer file.close();
    var writer = file.writer();
    for (result_list) |result| {
        try writer.print("{d:.4} {d:.4}\n", .{ result.discard_ratio, result.storage_server_uptime_ratio });
    }
    // Plot using python matplotlib.
    if (config.do_plot) {
        const argv: []const []const u8 = &.{ config.pyname, "plot.py", config.file_name };
        var child = std.process.Child.init(argv, config.allocator);
        try child.spawn();
        //_ = try child.wait();
    }
}

const builtin = @import("builtin");

/// Run simulation once, and return statistic result.
pub fn runOnce(
    allocator: std.mem.Allocator,
    interarrival_time: f64,
    complexity: f64,
    beta: usize,
    seed_base: u64,
    out_result: *SimulationResult,
) !void {
    var system = try simulation.System.init(
        allocator,
        beta,
        interarrival_time,
        complexity,
        0.1,
        15800,
        1600,
        seed_base,
        seed_base +% 100,
        seed_base +% 200,
        seed_base +% 300,
    );
    defer system.deinit();

    try system.step0();
    while (system.clock < 3600 * 8) {
        try system.step();
    }

    out_result.* = .{
        .discard_ratio = system.frame_discarded / system.frame_total,
        .storage_server_uptime_ratio = system.storage_server_uptime / system.clock,
    };
}

const simulation = @import("simulation.zig");

const std = @import("std");

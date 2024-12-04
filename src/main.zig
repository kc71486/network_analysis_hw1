/// Overrides options
pub const std_options = .{
    // Set the log level to warn
    .log_level = .warn,
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
    {
        const interarrival_time: f64 = 1.0 / 120.0;
        const complexity: f64 = 200.0;
        const beta_arr: [5]usize = .{ 20, 40, 60, 80, 100 };
        var result_list: [beta_arr.len]SimulationResult = .{undefined} ** beta_arr.len;
        for (beta_arr, 0..) |beta, idx| {
            result_list[idx] = try runOnce(allocator, interarrival_time, complexity, beta);
        }
        var file = try cwd.createFile("result1.txt", .{ .read = false });
        defer file.close();
        var writer = file.writer();
        for (result_list) |result| {
            try writer.print("{d:.4} {d:.4}\n", .{ result.discard_ratio, result.storage_server_uptime_ratio });
        }
    }
    {
        const interarrival_time: f64 = 1.0 / 240.0;
        const complexity: f64 = 400.0;
        const beta_arr: [5]usize = .{ 20, 40, 60, 80, 100 };
        var result_list: [beta_arr.len]SimulationResult = .{undefined} ** beta_arr.len;
        for (beta_arr, 0..) |beta, idx| {
            result_list[idx] = try runOnce(allocator, interarrival_time, complexity, beta);
        }
        var file = try cwd.createFile("result2.txt", .{ .read = false });
        defer file.close();
        var writer = file.writer();
        for (result_list) |result| {
            try writer.print("{d:.4} {d:.4}\n", .{ result.discard_ratio, result.storage_server_uptime_ratio });
        }
    }
}

pub fn runOnce(allocator: std.mem.Allocator, interarrival_time: f64, complexity: f64, beta: usize) !SimulationResult {
    std.log.info("interarrival time: {d:.4}, complexity: {d}, beta: {d}", .{ interarrival_time, complexity, beta });
    var system = try simulation.System.init(
        allocator,
        beta,
        interarrival_time,
        complexity,
        0.1,
        15800,
        1600,
        1100,
        1200,
        1300,
        1400,
    );
    defer system.deinit();
    try system.step0();
    while (system.clock < 3600 * 8) {
        try system.step();
    }
    std.log.info(
        "discarded: {d}, total: {d}, ratio: {d:.3}",
        .{ system.frame_discarded, system.frame_total, system.frame_discarded / system.frame_total },
    );
    std.log.info(
        "storage uptime: {d:.3}, total: {d:.3}, ratio: {d:.3}\n",
        .{ system.storage_server_uptime, system.clock, system.storage_server_uptime / system.clock },
    );
    return .{
        .discard_ratio = system.frame_discarded / system.frame_total,
        .storage_server_uptime_ratio = system.storage_server_uptime / system.clock,
    };
}

const simulation = @import("simulation.zig");

const std = @import("std");

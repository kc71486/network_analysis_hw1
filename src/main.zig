pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator: std.mem.Allocator = gpa.allocator();
    {
        const interarrival_time: f64 = 1.0 / 120.0;
        const complexity: f64 = 200.0;
        const beta_arr: [5]usize = .{ 20, 40, 60, 80, 100 };
        for (beta_arr) |beta| {
            try runOnce(allocator, interarrival_time, complexity, beta);
        }
    }
    {
        const interarrival_time: f64 = 1.0 / 240.0;
        const complexity: f64 = 400.0;
        const beta_arr: [5]usize = .{ 20, 40, 60, 80, 100 };
        for (beta_arr) |beta| {
            try runOnce(allocator, interarrival_time, complexity, beta);
        }
    }
}

pub fn runOnce(allocator: std.mem.Allocator, interarrival_time: f64, complexity: f64, beta: usize) !void {
    std.debug.print("interarrival time: {d:.4}, complexity: {d}, beta: {d}\n", .{ interarrival_time, complexity, beta });
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
    std.debug.print(
        "discarded: {d}, total: {d}, ratio: {d:.3}\n",
        .{ system.frame_discarded, system.frame_total, system.frame_discarded / system.frame_total },
    );
    std.debug.print(
        "storage uptime: {d:.3}, total: {d:.3}, ratio: {d:.3}\n\n",
        .{ system.storage_server_uptime, system.clock, system.storage_server_uptime / system.clock },
    );
}

const simulation = @import("simulation.zig");

const std = @import("std");

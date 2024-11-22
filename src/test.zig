test "integration test" {
    const test_alloc = std.testing.allocator;

    {
        const interarrival_time: f64 = 1.0 / 120.0;
        const complexity: f64 = 200.0;
        const beta_arr: [7]usize = .{ 2, 5, 20, 40, 60, 80, 100 };
        for (beta_arr) |beta| {
            try runOnce(test_alloc, interarrival_time, complexity, beta, 1000);
        }
    }
    {
        const interarrival_time: f64 = 1.0 / 240.0;
        const complexity: f64 = 400.0;
        const beta_arr: [7]usize = .{ 2, 5, 20, 40, 60, 80, 100 };
        for (beta_arr) |beta| {
            try runOnce(test_alloc, interarrival_time, complexity, beta, 1000);
        }
    }
}

test "Simulation steps" {
    const test_alloc = std.testing.allocator;
    var system = try simulation.System.init(
        test_alloc,
        20,
        1.0 / 120.0,
        200.0,
        0.1,
        15800,
        1600,
        1100,
        1200,
        1300,
        1400,
    );
    try system.step0();
    for (0..1000) |_| {
        try system.step();
    }
    defer system.deinit();
}

test "floatexp" {
    var prng = std.Random.Xoshiro256.init(1);
    const random = prng.random();
    var f = random.floatExp(f64);
    _ = &f;
}

pub fn runOnce(allocator: std.mem.Allocator, interarrival_time: f64, complexity: f64, beta: usize, seed_base: u64) !void {
    var system = try simulation.System.init(
        allocator,
        beta,
        interarrival_time,
        complexity,
        0.1,
        15800,
        1600,
        seed_base + 100,
        seed_base + 200,
        seed_base + 300,
        seed_base + 400,
    );
    defer system.deinit();
    try system.step0();
    while (system.clock < 3600 * 8) {
        try system.step();
    }
}

const simulation = @import("simulation.zig");
const std = @import("std");

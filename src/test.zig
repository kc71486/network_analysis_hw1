test "integration test" {
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
    while (system.clock < 3600 * 8) {
        try system.step();
    }
    defer system.deinit();
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

const simulation = @import("simulation.zig");
const std = @import("std");

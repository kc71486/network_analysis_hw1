pub const System = struct {
    queue_encoder_buffer_limit: usize,
    mean_inter_arrival_time: f64,
    mean_frame_complexity: f64,
    frame_size_complexity_ratio: f64,
    process_capacity_encoder: f64,
    process_capacity_storage: f64,
    event_list: EventList,
    queue_encoder: DequeFixed(Field),
    queue_storage: DequeUnmanaged(Field),
    clock: f64,
    encoder_field: ?Field,
    storage_busy: bool,
    prev_top_deleted: bool,
    frame_discarded: f64,
    frame_total: f64,
    storage_server_uptime: f64,
    prng_arrival_top: std.Random.Xoshiro256,
    prng_arrival_bottom: std.Random.Xoshiro256,
    prng_complexity_top: std.Random.Xoshiro256,
    prng_complexity_bottom: std.Random.Xoshiro256,
    allocator: std.mem.Allocator,

    /// Initialize variables. Need to run `step0()` before starting.
    pub fn init(
        allocator: std.mem.Allocator,
        queue_encoder_buffer_limit: usize,
        mean_inter_arrival_time: f64,
        mean_frame_complexity: f64,
        frame_size_complexity_ratio: f64,
        process_capacity_encoder: f64,
        process_capacity_storage: f64,
        seed_arrival_top: u64,
        seed_arrival_bottom: u64,
        seed_complexity_top: u64,
        seed_complexity_bottom: u64,
    ) !System {
        if (queue_encoder_buffer_limit <= 1) {
            // Encoder with buffer <= 1 will always throw away data.
            return error.EncoderBufferTooShort;
        }
        if (process_capacity_encoder * frame_size_complexity_ratio / process_capacity_storage > 1.5) {
            // Storage server process speed is slower than field produce speed by a large margin.
            return error.StorageServerTooSlow;
        }
        return .{
            .queue_encoder_buffer_limit = queue_encoder_buffer_limit,
            .mean_inter_arrival_time = mean_inter_arrival_time,
            .mean_frame_complexity = mean_frame_complexity,
            .frame_size_complexity_ratio = frame_size_complexity_ratio,
            .process_capacity_encoder = process_capacity_encoder,
            .process_capacity_storage = process_capacity_storage,
            .event_list = EventList.init(),
            .queue_encoder = try DequeFixed(Field).initCapacity(allocator, queue_encoder_buffer_limit),
            .queue_storage = try DequeUnmanaged(Field).initCapacity(allocator, 40),
            .clock = 0,
            .encoder_field = null,
            .storage_busy = false,
            .prev_top_deleted = false,
            .frame_discarded = 0,
            .frame_total = 0,
            .storage_server_uptime = 0,
            .prng_arrival_top = std.Random.Xoshiro256.init(seed_arrival_top),
            .prng_arrival_bottom = std.Random.Xoshiro256.init(seed_arrival_bottom),
            .prng_complexity_top = std.Random.Xoshiro256.init(seed_complexity_top),
            .prng_complexity_bottom = std.Random.Xoshiro256.init(seed_complexity_bottom),
            .allocator = allocator,
        };
    }
    pub fn deinit(this: *System) void {
        this.queue_encoder.deinit(this.allocator);
        this.queue_storage.deinit(this.allocator);
    }
    /// First step, initiate first event. Note: `System.init()` is the one that initialize variables.
    pub fn step0(this: *System) !void {
        var random: std.Random = this.prng_arrival_top.random();
        const inter_arrival_time = random.floatExp(f64) * this.mean_inter_arrival_time;
        const new_field: Field = .{
            .is_top = true,
            .complexity = random.floatExp(f64) * this.mean_frame_complexity,
        };
        this.event_list.add(.arrival_encoder, .{
            .clock = inter_arrival_time,
            .tag = .arrival_encoder,
            .field = new_field,
        });
    }
    /// All subsequent steps. Updates state every time this function is called.
    pub fn step(this: *System) !void {
        var event: Event = try this.getEvent();
        _ = &event;
        const next_clock: f64 = event.clock;
        if (this.storage_busy) {
            this.storage_server_uptime += next_clock - this.clock;
        }
        switch (event.tag) {
            .arrival_encoder => {
                try this.handleArrivalEncoder(event, next_clock);
            },
            .departure_encoder_arrival_storage => {
                try this.handleDepartureEncoderArrivalStorage(event, next_clock);
            },
            .departure_storage => {
                try this.handleDepartureStorage(next_clock);
            },
            .invalid => @panic("invalid event"),
        }
        this.clock = next_clock;
    }
    fn getEvent(this: *System) !Event {
        var event: Event = .{
            .clock = std.math.inf(f64),
            .tag = .invalid,
            .field = undefined,
        };
        var event_idx: usize = 0;
        const event_tag_arr: []const EnumField = @typeInfo(Event.Tag).@"enum".fields;
        inline for (event_tag_arr) |event_tag| {
            const ev_opt = this.event_list.items[event_tag.value];
            if (ev_opt) |ev| {
                if (ev.clock <= event.clock) {
                    event = ev;
                    event_idx = event_tag.value;
                }
            }
        }
        assert(this.event_list.items[@intFromEnum(Event.Tag.arrival_encoder)] != null);
        assert(this.event_list.items[@intFromEnum(Event.Tag.invalid)] == null);

        this.event_list.items[event_idx] = null;
        assert(event.clock != std.math.inf(f64));
        assert(event.tag != .invalid);

        return event;
    }
    /// Handle encoder arrival event.
    fn handleArrivalEncoder(this: *System, event: Event, next_clock: f64) !void {
        assert(event.field != null);
        assert(this.queue_encoder_buffer_limit >= 2);
        const cur_field: Field = event.field.?;
        const is_full: bool = this.queue_encoder.size() == this.queue_encoder_buffer_limit;
        // Determine if keep (add queue) or discard (frame_discarded +).
        if (this.prev_top_deleted) {
            assert(!cur_field.is_top); // Only happens when current is bottom.
            this.frame_discarded += 1;
            this.prev_top_deleted = false;
        } else if (is_full) {
            if (cur_field.is_top) {
                this.frame_discarded += 1;
                this.prev_top_deleted = true;
            } else {
                assert(this.queue_encoder.peekLast().is_top);
                _ = this.queue_encoder.popLast();
                this.frame_discarded += 2;
                this.prev_top_deleted = false;
            }
        } else {
            this.queue_encoder.pushLast(cur_field);
            this.prev_top_deleted = false;
        }
        this.frame_total += 1;

        // Schedule departure if server is empty and queue have something.
        if (this.encoder_field) |_| {
            // server busy
        } else if (this.queue_encoder.size() > 0) {
            assert(this.queue_encoder.size() == 1);
            const first_field: Field = this.queue_encoder.popFirst();
            const server_process_time: f64 = first_field.complexity / this.process_capacity_encoder;
            this.event_list.add(.departure_encoder_arrival_storage, .{
                .clock = next_clock + server_process_time,
                .tag = .departure_encoder_arrival_storage,
                .field = first_field,
            });
            this.encoder_field = first_field;
        } else {
            // Happens when previous top got discarded, and the queue got emptied.
            assert(!cur_field.is_top);
            assert(!this.prev_top_deleted);
        }
        var random_arrival: std.Random = undefined;
        var random_complexity: std.Random = undefined;
        if (cur_field.is_top) {
            random_arrival = this.prng_arrival_top.random();
            random_complexity = this.prng_complexity_top.random();
        } else {
            random_arrival = this.prng_arrival_bottom.random();
            random_complexity = this.prng_complexity_bottom.random();
        }
        // schedule arrival
        const inter_arrival_time = random_arrival.floatExp(f64) * this.mean_inter_arrival_time;
        const new_field: Field = .{
            .is_top = !cur_field.is_top, // invert
            .complexity = random_complexity.floatExp(f64) * this.mean_frame_complexity,
        };
        this.event_list.add(.arrival_encoder, .{
            .clock = next_clock + inter_arrival_time,
            .tag = .arrival_encoder,
            .field = new_field,
        });
    }
    /// Handle encoder departure and storage arrival event.
    fn handleDepartureEncoderArrivalStorage(this: *System, event: Event, next_clock: f64) !void {
        assert(this.encoder_field != null);
        // departure_encoder part
        if (this.queue_encoder.size() == 0) {
            this.encoder_field = null;
        } else {
            const first_field: Field = this.queue_encoder.popFirst();
            const server_process_time: f64 = first_field.complexity / this.process_capacity_encoder;
            this.event_list.add(.departure_encoder_arrival_storage, .{
                .clock = next_clock + server_process_time,
                .tag = .departure_encoder_arrival_storage,
                .field = first_field,
            });
            this.encoder_field = first_field;
        }
        // arrival_storage part
        const cur_field: Field = event.field.?;
        try this.queue_storage.pushLast(this.allocator, cur_field);
        if (!this.storage_busy) {
            if (this.queue_storage.size() == 2) {
                const top_field: Field = this.queue_storage.popFirst();
                const bottom_field: Field = this.queue_storage.popFirst();
                assert(top_field.is_top);
                assert(!bottom_field.is_top);
                const storage_time: f64 = (top_field.complexity + bottom_field.complexity) * this.frame_size_complexity_ratio / this.process_capacity_storage;
                this.event_list.add(.departure_storage, .{
                    .clock = next_clock + storage_time,
                    .tag = .departure_storage,
                    .field = null, // field drain
                });
                this.storage_busy = true;
            }
        }
    }
    /// Handle storage departure event.
    fn handleDepartureStorage(this: *System, next_clock: f64) !void {
        assert(this.storage_busy);
        if (this.queue_storage.size() >= 2) {
            const top_field: Field = this.queue_storage.popFirst();
            const bottom_field: Field = this.queue_storage.popFirst();
            assert(top_field.is_top);
            assert(!bottom_field.is_top);
            const storage_time: f64 = (top_field.complexity + bottom_field.complexity) * this.frame_size_complexity_ratio / this.process_capacity_storage;
            this.event_list.add(.departure_storage, .{
                .clock = next_clock + storage_time,
                .tag = .departure_storage,
                .field = null, // field drain
            });
        } else {
            this.storage_busy = false;
        }
    }
};

const Field = struct {
    is_top: bool,
    complexity: f64,
};

const EventList = struct {
    const item_len: usize = @typeInfo(Event.Tag).@"enum".fields.len;

    /// Underlying array.
    items: [item_len]?Event,

    pub fn init() EventList {
        return .{
            .items = .{null} ** item_len,
        };
    }
    // Add the event with tag
    pub fn add(this: *EventList, tag: Event.Tag, event: Event) void {
        assert(this.items[@intFromEnum(tag)] == null);
        this.items[@intFromEnum(tag)] = event;
    }
    // Remove the event with tag
    pub fn remove(this: *EventList, tag: Event.Tag) void {
        assert(this.items[@intFromEnum(tag)] != null);
        this.items[@intFromEnum(tag)] = null;
    }
    // Get the value from tag
    pub fn get(this: *const EventList, tag: Event.Tag) *Event {
        return *this.items[@intFromEnum(tag)];
    }
};

const Event = struct {
    clock: f64,
    tag: Tag,
    field: ?Field,

    const Tag = enum(u32) {
        arrival_encoder,
        departure_encoder_arrival_storage,
        departure_storage,
        invalid,
    };
};

pub fn assert(ok: bool) void {
    if (!ok) {
        @panic("assertion failure.");
    }
}

const DequeUnmanaged = @import("deque.zig").DequeUnmanaged;
const DequeFixed = @import("deque.zig").DequeFixed;

const std = @import("std");
const EnumField = std.builtin.Type.EnumField;

const std = @import("std");
const testing = std.testing;
const math = std.math;
const Allocator = std.mem.Allocator;

fn assert(ok: bool) void {
    if (!ok) {
        unreachable;
    }
}

/// Fixed size deque.
pub fn DequeFixed(comptime T: type) type {
    assert(@sizeOf(T) > 0);
    return struct {
        const This = @This();

        backing_array: []T,
        first: ?usize,
        last: ?usize,

        pub fn initCapacity(allocator: Allocator, num: usize) Allocator.Error!This {
            assert(num > 0);
            return .{
                .backing_array = try allocator.alloc(T, num),
                .first = null,
                .last = null,
            };
        }

        pub fn deinit(this: *This, allocator: Allocator) void {
            allocator.free(this.backing_array);
            this.* = undefined;
        }

        pub fn size(this: *const This) usize {
            this.assertFirstLast();
            if (this.first == null) {
                return 0;
            } else {
                return (this.last.? + this.capacity() - this.first.?) % this.capacity() + 1;
            }
        }

        pub fn capacity(this: *const This) usize {
            return this.backing_array.len;
        }

        pub fn isEmpty(this: *const This) bool {
            this.assertFirstLast();
            return this.first == null;
        }

        pub fn isFull(this: *const This) bool {
            return this.size() == this.capacity();
        }

        pub fn pushLast(this: *This, item: T) void {
            assert(!this.isFull());
            this.assertFirstLast();
            if (this.last) |last| {
                this.last = (last + 1) % this.capacity();
            } else {
                this.first = 0;
                this.last = 0;
            }
            this.backing_array[this.last.?] = item;
        }

        pub fn pushFirst(this: *This, item: T) void {
            assert(!this.isFull());
            this.assertFirstLast();
            if (this.first) |first| {
                this.first = (first + this.capacity() - 1) % this.capacity();
            } else {
                this.first = 0;
                this.last = 0;
            }
            this.backing_array[this.first.?] = item;
        }

        pub fn popLast(this: *This) T {
            assert(!this.isEmpty());
            const result = this.backing_array[this.last.?];
            if (this.size() == 1) {
                this.first = null;
                this.last = null;
            } else {
                this.backing_array[this.last.?] = undefined;
                this.last = (this.last.? + this.capacity() - 1) % this.capacity();
            }
            return result;
        }

        pub fn popFirst(this: *This) T {
            assert(!this.isEmpty());
            const result = this.backing_array[this.first.?];
            if (this.size() == 1) {
                this.first = null;
                this.last = null;
            } else {
                this.backing_array[this.first.?] = undefined;
                this.first = (this.first.? + 1) % this.capacity();
            }
            return result;
        }

        pub fn peekLast(this: *const This) T {
            assert(!this.isEmpty());
            return this.backing_array[this.last.?];
        }

        pub fn peekFirst(this: *const This) T {
            assert(!this.isEmpty());
            return this.backing_array[this.first.?];
        }

        fn assertFirstLast(this: *const This) void {
            const both_or_neither: bool = (this.first != null) == (this.last != null);
            assert(both_or_neither);
        }
    };
}

// Resizeable deque, ArrayList under the hood.
pub fn DequeUnmanaged(comptime T: type) type {
    assert(@sizeOf(T) > 0);
    return struct {
        const This = @This();

        items: Slice,
        capacity: usize,

        pub const empty: This = .{
            .items = &.{},
            .capacity = 0,
        };

        pub const Slice = []T;

        pub fn initCapacity(allocator: Allocator, num: usize) Allocator.Error!This {
            var this = empty;

            if (num == 0) {
                return this;
            }

            const new_memory = try allocator.alloc(T, num);
            this.items.ptr = new_memory.ptr;
            this.capacity = new_memory.len;

            return this;
        }

        pub fn deinit(this: *This, allocator: Allocator) void {
            allocator.free(this.allocatedSlice());
            this.* = undefined;
        }

        pub fn size(this: *const This) usize {
            return this.items.len;
        }

        pub fn capacity_(this: *const This) usize {
            return this.capacity;
        }

        pub fn isEmpty(this: *const This) bool {
            return this.size() == 0;
        }

        pub fn isFull(this: *const This) bool {
            return this.size() == this.capacity();
        }

        pub fn pushLast(this: *This, allocator: Allocator, item: T) !void {
            const newlen = this.items.len + 1;
            try this.ensureTotalCapacity(allocator, newlen);
            assert(this.items.len < this.capacity);
            this.items.len += 1;
            this.items[this.items.len - 1] = item;
        }

        pub fn pushFirst(this: *This, allocator: Allocator, item: T) !void {
            const new_len = try addOrOom(this.items.len, 1);

            if (this.capacity >= new_len) {
                const dst: *T = this.addOneAtAssumeCapacity(0);
                dst.* = item;
                return;
            }

            // Check if able to resize in place.
            const new_capacity = growCapacity(this.capacity, new_len);
            const old_memory = this.allocatedSlice();
            if (allocator.resize(old_memory, new_capacity)) {
                this.capacity = new_capacity;
                const dst: *T = this.addOneAtAssumeCapacity(0);
                dst.* = item;
                return;
            }

            // Unable to resize in place.
            const new_memory = try allocator.alloc(T, new_capacity);
            const to_move = this.items;
            @memcpy(new_memory[1..][0..to_move.len], to_move);
            allocator.free(old_memory);
            this.items = new_memory[0..new_len];
            this.capacity = new_memory.len;
            // The inserted elements at `new_memory[0..count]` have
            // already been set to `undefined` by memory allocation.
            const dst: *T = &new_memory[0];
            dst.* = item;
        }

        pub fn popLast(this: *This) T {
            const val = this.items[this.items.len - 1];
            this.items.len -= 1;
            return val;
        }

        pub fn popFirst(this: *This) T {
            const old_item = this.items[0];
            std.mem.copyForwards(T, this.items, this.items[1..]);
            this.items[this.items.len - 1] = undefined;
            this.items.len -= 1;
            return old_item;
        }

        pub fn peekLast(this: *const This) T {
            return this.items[this.items.len - 1];
        }

        pub fn peekFirst(this: *const This) T {
            return this.items[0];
        }

        pub fn addOneAtAssumeCapacity(this: *This, index: usize) *T {
            const new_len = this.items.len + 1;
            assert(this.capacity >= new_len);
            const to_move = this.items[index..];
            this.items.len = new_len;
            std.mem.copyBackwards(T, this.items[index + 1 ..], to_move);
            const result: *T = &this.items[index];
            result.* = undefined;
            return result;
        }

        pub fn ensureTotalCapacity(this: *This, allocator: Allocator, minimum_capacity: usize) Allocator.Error!void {
            if (this.capacity >= minimum_capacity) return;

            const new_capacity = growCapacity(this.capacity, minimum_capacity);

            if (@sizeOf(T) == 0) {
                this.capacity = math.maxInt(usize);
                return;
            }

            if (this.capacity >= new_capacity) return;

            const old_memory = this.allocatedSlice();
            if (allocator.resize(old_memory, new_capacity)) {
                this.capacity = new_capacity;
            } else {
                const new_memory = try allocator.alignedAlloc(T, null, new_capacity);
                @memcpy(new_memory[0..this.items.len], this.items);
                allocator.free(old_memory);
                this.items.ptr = new_memory.ptr;
                this.capacity = new_memory.len;
            }
        }

        pub fn allocatedSlice(this: This) Slice {
            return this.items.ptr[0..this.capacity];
        }
    };
}

/// Called when memory growth is necessary. Returns a capacity larger than
/// minimum that grows super-linearly.
fn growCapacity(current: usize, minimum: usize) usize {
    var new = current;
    while (true) {
        new +|= new / 2 + 8;
        if (new >= minimum)
            return new;
    }
}

/// Integer addition returning `error.OutOfMemory` on overflow.
fn addOrOom(a: usize, b: usize) error{OutOfMemory}!usize {
    const result, const overflow = @addWithOverflow(a, b);
    if (overflow != 0) return error.OutOfMemory;
    return result;
}

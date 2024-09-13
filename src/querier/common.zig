const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn Envelope(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T = undefined,
        arena: ArenaAllocator,

        pub fn deinit(self: Self) void {
            self.arena.deinit();
        }
    };
}

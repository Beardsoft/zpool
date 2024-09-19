const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn ArenaWrapped(comptime T: type) type {
    return struct {
        const Self = @This();

        arena: ArenaAllocator,
        value: T,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }
    };
}

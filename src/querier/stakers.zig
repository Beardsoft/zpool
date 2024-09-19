const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const sqlite = @import("../sqlite.zig");
const ArenaWrapped = @import("../utils.zig").ArenaWrapped;

pub fn insertNewStaker(conn: *sqlite.Conn, address: []const u8, epoch_number: u32, stake_balance: u64, stake_percentage: f64) !void {
    try conn.exec("REPLACE INTO stakers(address, epoch_number, stake_balance, stake_percentage) VALUES(?1, ?2, ?3, ?4);", .{ address, epoch_number, stake_balance, stake_percentage });
}

pub const GetStakersByEpochRow = struct {
    address: []u8,
    stake_percentage: f64,
};

pub fn getStakersByEpoch(conn: *sqlite.Conn, allocator: Allocator, epoch_number: u32) !ArenaWrapped([]GetStakersByEpochRow) {
    var rows = try conn.rows("SELECT address, stake_percentage FROM stakers WHERE epoch_number = ?1;", .{epoch_number});
    defer rows.deinit();

    var arena = ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();

    var array_list = std.ArrayList(GetStakersByEpochRow).init(arena_allocator);

    while (rows.next()) |row| {
        var address = row.text(0);
        const stake_percentage = row.float(1);

        const address_copy = try arena_allocator.alloc(u8, address.len);
        @memcpy(address_copy, address[0..]);

        try array_list.append(GetStakersByEpochRow{ .address = address_copy, .stake_percentage = stake_percentage });
    }

    const data = try array_list.toOwnedSlice();
    return ArenaWrapped([]GetStakersByEpochRow){ .arena = arena, .value = data };
}

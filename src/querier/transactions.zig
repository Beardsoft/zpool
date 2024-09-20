const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;
const ArenaWrapped = @import("../utils.zig").ArenaWrapped;

pub fn insertNewTransaction(conn: *sqlite.Conn, hash: []u8, address: []u8, amount: u64, status: Status) !void {
    try conn.exec("INSERT INTO transactions(hash, address, amount, status_id) VALUES(?1, ?2, ?3, ?4);", .{ hash, address, amount, @intFromEnum(status) });
}

pub const GetTransactionHashesAwaitingConfirmationRow = struct {
    hash: []u8,
};

pub fn getTransactionHashesAwaitingConfirmation(conn: *sqlite.Conn, allocator: Allocator) !ArenaWrapped([]GetTransactionHashesAwaitingConfirmationRow) {
    var rows = try conn.rows("SELECT hash FROM transactions WHERE status_id = ?1", .{@intFromEnum(Status.AwaitingConfirmation)});
    defer rows.deinit();

    var arena = ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();

    var array_list = std.ArrayList(GetTransactionHashesAwaitingConfirmationRow).init(arena_allocator);

    while (rows.next()) |row| {
        const hash = row.text(0);
        const hash_copy = try Allocator.dupe(arena_allocator, u8, hash);

        try array_list.append(GetTransactionHashesAwaitingConfirmationRow{ .hash = hash_copy });
    }

    const data = try array_list.toOwnedSlice();
    return ArenaWrapped([]GetTransactionHashesAwaitingConfirmationRow){ .arena = arena, .value = data };
}

pub fn setStatus(conn: *sqlite.Conn, hash: []u8, status: Status) !void {
    try conn.exec("UPDATE transactions SET status_id = ?1 WHERE hash = ?2;", .{ @intFromEnum(status), hash });
}

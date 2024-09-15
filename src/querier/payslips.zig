const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;
const Envelope = @import("common.zig").Envelope;

pub fn insertNewPayslip(conn: *sqlite.Conn, collection_number: u64, address: []u8, amount: u64, status: Status) !void {
    try conn.exec("INSERT INTO payslips(collection_number, address, amount, status_id) VALUES(?1, ?2, ?3, ?4);", .{ collection_number, address, amount, @intFromEnum(status) });
}

pub const GetPendingHigherThanMinPayoutRow = struct {
    address: []u8,
    amount: u64,
};

pub fn getPendingHigherThanMinPayout(conn: *sqlite.Conn, allocator: Allocator) !Envelope(GetPendingHigherThanMinPayoutRow) {
    var rows = try conn.rows("SELECT SUM(amount), address FROM payslips WHERE status_id = 7 GROUP BY address HAVING SUM(amount) > 1000000", .{});
    defer rows.deinit();

    var arena = ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();

    var array_list = std.ArrayList(GetPendingHigherThanMinPayoutRow).init(arena_allocator);

    while (rows.next()) |row| {
        const amount = @as(u64, @intCast(row.int(0)));
        var address = row.text(1);

        const address_copy = try arena_allocator.alloc(u8, address.len);
        @memcpy(address_copy, address[0..]);

        try array_list.append(GetPendingHigherThanMinPayoutRow{ .address = address_copy, .amount = amount });
    }

    const data = try array_list.toOwnedSlice();
    return Envelope(GetPendingHigherThanMinPayoutRow){ .arena = arena, .data = data };
}

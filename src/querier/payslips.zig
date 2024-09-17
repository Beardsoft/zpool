const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;
const Envelope = @import("common.zig").Envelope;

pub fn insertNewPayslip(conn: *sqlite.Conn, collection_number: u32, address: []u8, amount: u64, status: Status) !void {
    try conn.exec("INSERT INTO payslips(collection_number, address, amount, status_id) VALUES(?1, ?2, ?3, ?4);", .{ collection_number, address, amount, @intFromEnum(status) });
}

pub fn setElligableToOutForPayment(conn: *sqlite.Conn) !void {
    // TODO: the min payout of 10 NIM should be configurable
    const min_payout_amount = 10 * 100000;
    try conn.exec("UPDATE payslips SET status_id = ?1 WHERE status_id = ?2 AND address in (SELECT address FROM payslips WHERE status_id = ?3 GROUP BY address HAVING sum(amount) > ?4);", .{ @intFromEnum(Status.OutForPayment), @intFromEnum(Status.Pending), @intFromEnum(Status.Pending), min_payout_amount });
}

pub const GetOutForPaymentRow = struct {
    address: []u8,
    amount: u64,
};

pub fn getOutForPayment(conn: *sqlite.Conn, allocator: Allocator) !Envelope(GetOutForPaymentRow) {
    var rows = try conn.rows("SELECT SUM(amount), address FROM payslips WHERE status_id = 8 GROUP BY address;", .{});
    defer rows.deinit();

    var arena = ArenaAllocator.init(allocator);
    var arena_allocator = arena.allocator();

    var array_list = std.ArrayList(GetOutForPaymentRow).init(arena_allocator);

    while (rows.next()) |row| {
        const amount = @as(u64, @intCast(row.int(0)));
        var address = row.text(1);

        const address_copy = try arena_allocator.alloc(u8, address.len);
        @memcpy(address_copy, address[0..]);

        try array_list.append(GetOutForPaymentRow{ .address = address_copy, .amount = amount });
    }

    const data = try array_list.toOwnedSlice();
    return Envelope(GetOutForPaymentRow){ .arena = arena, .data = data };
}

pub fn setTransaction(conn: *sqlite.Conn, hash: []u8, address: []u8) !void {
    try conn.exec("UPDATE payslips SET tx_hash = ?1, status_id = ?2 WHERE address = ?3 AND status_id = ?4;", .{ hash, @intFromEnum(Status.AwaitingConfirmation), address, @intFromEnum(Status.OutForPayment) });
}

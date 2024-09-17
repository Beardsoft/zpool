const std = @import("std");
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;

pub fn insertNewTransaction(conn: *sqlite.Conn, hash: []u8, address: []u8, amount: u64, status: Status) !void {
    try conn.exec("INSERT INTO transactions(hash, address, amount, status_id) VALUES(?1, ?2, ?3, ?4);", .{ hash, address, amount, @intFromEnum(status) });
}

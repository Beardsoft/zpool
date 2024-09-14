const std = @import("std");
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;

pub fn insertNewPayslip(conn: *sqlite.Conn, collection_number: u64, address: []u8, amount: u64, status: Status) !void {
    try conn.exec("INSERT INTO payslips(collection_number, address, amount, status_id) VALUES(?1, ?2, ?3, ?4);", .{ collection_number, address, amount, @intFromEnum(status) });
}

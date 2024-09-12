const std = @import("std");
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;

pub fn epochExists(conn: *sqlite.Conn, epoch_number: u64) !bool {
    const result = try conn.row("SELECT number FROM epochs WHERE number = ?1;", .{epoch_number});
    if (result) |row| {
        defer row.deinit();
        return true;
    }
    return false;
}

pub fn insertNewEpoch(conn: *sqlite.Conn, epoch_number: u64, num_stakers: u64, balance: u64, status: Status) !void {
    try conn.exec("INSERT INTO epochs(number, num_stakers, balance, status_id) VALUES(?1, ?2, ?3, ?4)", .{ epoch_number, num_stakers, balance, @intFromEnum(status) });
}
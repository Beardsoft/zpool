const std = @import("std");
const sqlite = @import("../sqlite.zig");
const Status = @import("statuses.zig").Status;

pub const QueryError = error{
    NotFound,
};

pub fn epochExists(conn: *sqlite.Conn, epoch_number: u32) !bool {
    const result = try conn.row("SELECT number FROM epochs WHERE number = ?1;", .{epoch_number});
    if (result) |row| {
        defer row.deinit();
        return true;
    }
    return false;
}

pub fn insertNewEpoch(conn: *sqlite.Conn, epoch_number: u32, num_stakers: u16, balance: u64, status: Status) !void {
    try conn.exec("INSERT INTO epochs(number, num_stakers, balance, status_id) VALUES(?1, ?2, ?3, ?4)", .{ epoch_number, num_stakers, balance, @intFromEnum(status) });
}

pub const GetEpochDetailsByNumberRow = struct {
    status: Status,
    num_stakers: u16,
};

pub fn getEpochDetailsByNumber(conn: *sqlite.Conn, epoch_number: u32) !GetEpochDetailsByNumberRow {
    const result = try conn.row("SELECT status_id, num_stakers FROM epochs WHERE number = ?1;", .{epoch_number});
    if (result) |row| {
        defer row.deinit();
        const status_id = row.int(0);
        const status: Status = @enumFromInt(status_id);
        const num_stakers = @as(u16, @intCast(row.int(1)));
        return .{ .status = status, .num_stakers = num_stakers };
    }

    return QueryError.NotFound;
}

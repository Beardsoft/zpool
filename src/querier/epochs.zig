const std = @import("std");
const Allocator = std.mem.Allocator;
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

pub const GetPaymentsCompletedByInProgressRow = struct {
    number_of_payments: u32,
    epoch_number: u32,
    num_stakers: u32,
};

pub fn getPaymentsCompletedByInProgress(conn: *sqlite.Conn, allocator: Allocator) ![]GetPaymentsCompletedByInProgressRow {
    var rows = try conn.rows("SELECT COUNT(p.collection_number), r.epoch_number, e.num_stakers FROM payslips AS p LEFT JOIN rewards AS r ON p.collection_number == r.collection_number LEFT JOIN epochs AS e ON r.epoch_number = e.number WHERE p.status_id = 6 AND e.status_id = 5 GROUP BY r.epoch_number;", .{});
    defer rows.deinit();

    var list = std.ArrayList(GetPaymentsCompletedByInProgressRow).init(allocator);

    while (rows.next()) |row| {
        try list.append(GetPaymentsCompletedByInProgressRow{ .number_of_payments = @as(u32, @intCast(row.int(0))), .epoch_number = @as(u32, @intCast(row.int(1))), .num_stakers = @as(u32, @intCast(row.int(2))) });
    }

    return list.toOwnedSlice();
}

pub fn setStatus(conn: *sqlite.Conn, number: u32, status: Status) !void {
    try conn.exec("UPDATE epochs SET status_id = ?1 WHERE number = ?2;", .{ @intFromEnum(status), number });
}

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

const finalizeCompletedQuery =
    \\UPDATE epochs SET status_id = 6 WHERE number IN (
    \\    SELECT r.epoch_number
    \\    FROM rewards AS r
    \\    INNER JOIN (
    \\        SELECT COUNT(collection_number) AS count, collection_number
    \\        FROM payslips 
    \\        WHERE status_id = 6
    \\        GROUP BY collection_number
    \\    ) AS p 
    \\        ON p.collection_number = r.collection_number
    \\    LEFT JOIN epochs AS e ON r.epoch_number = e.number 
    \\    WHERE e.status_id = 5 GROUP BY r.epoch_number
    \\    HAVING SUM(p.count) = SUM(r.num_payments)
    \\) RETURNING number;
;

pub fn finalizeCompleted(conn: *sqlite.Conn, allocator: Allocator) ![]u32 {
    var rows = try conn.rows(finalizeCompletedQuery, .{});
    defer rows.deinit();

    var list = std.ArrayList(u32).init(allocator);

    while (rows.next()) |row| {
        try list.append(@as(u32, @intCast(row.int(0))));
    }

    return list.toOwnedSlice();
}

pub fn setStatus(conn: *sqlite.Conn, number: u32, status: Status) !void {
    try conn.exec("UPDATE epochs SET status_id = ?1 WHERE number = ?2;", .{ @intFromEnum(status), number });
}

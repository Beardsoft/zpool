const std = @import("std");
const sqlite = @import("../sqlite.zig");

pub fn getLastPollerHeight(conn: *sqlite.Conn) !u64 {
    const result = conn.row("SELECT block_number FROM cursors WHERE id = 1;", .{}) catch |err| {
        std.log.err("failed to fetch latest poller height: {}", .{err});
        return err;
    };

    if (result) |row| {
        defer row.deinit();
        return @intCast(row.int(0));
    }

    return 0;
}

pub fn upsertPollerHeight(conn: *sqlite.Conn, new_height: u64) !void {
    try conn.exec("REPLACE INTO cursors(id, block_number) VALUES(1, ?1);", .{new_height});
}

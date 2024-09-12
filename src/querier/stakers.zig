const std = @import("std");
const sqlite = @import("../sqlite.zig");

pub fn insertNewStaker(conn: *sqlite.Conn, address: []const u8, epoch_number: u64, stake_balance: u64, stake_percentage: f64) !void {
    try conn.exec("REPLACE INTO stakers(address, epoch_number, stake_balance, stake_percentage) VALUES(?1, ?2, ?3, ?4);", .{ address, epoch_number, stake_balance, stake_percentage });
}

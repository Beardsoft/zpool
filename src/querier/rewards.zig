const std = @import("std");
const sqlite = @import("../sqlite.zig");

pub fn insertNewReward(conn: *sqlite.Conn, epoch_number: u32, collection_number: u32, reward: u64, pool_fee: u64, num_payments: u16) !void {
    try conn.exec("INSERT INTO rewards(epoch_number, collection_number, reward, pool_fee, num_payments) VALUES(?1, ?2, ?3, ?4, ?5);", .{ epoch_number, collection_number, reward, pool_fee, num_payments });
}

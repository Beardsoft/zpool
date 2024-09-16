const std = @import("std");
const sqlite = @import("../sqlite.zig");

pub fn insertNewReward(conn: *sqlite.Conn, epoch_number: u32, collection_number: u32, reward: u64, pool_fee: u64) !void {
    try conn.exec("INSERT INTO rewards(epoch_number, collection_number, reward, pool_fee) VALUES(?1, ?2, ?3, ?4);", .{ epoch_number, collection_number, reward, pool_fee });
}

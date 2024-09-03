const std = @import("std");
const http = std.http;

const Config = @import("config.zig");
const db = @import("db.zig");
const poller = @import("poller.zig");

const zpool = @import("zpool");
const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var cfg = Config{};
    const uri = try std.Uri.parse(cfg.rpc_url);
    var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };
    var new_poller = poller{ .cfg = &cfg, .client = &jsonrpc_client, .allocator = allocator };

    _ = try db.init(cfg.sqlite_db_path);

    try new_poller.watchChainHeight();
}

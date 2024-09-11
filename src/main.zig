const std = @import("std");
const http = std.http;
const testing = std.testing;

const Config = @import("config.zig");
const poller = @import("poller.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");

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

    var sqlite_conn = try sqlite.open(cfg.sqlite_db_path);
    querier.migrate.execute(&sqlite_conn) catch |err| {
        std.log.err("executing migration failed: {}", .{err});
        return;
    };

    new_poller.watchChainHeight() catch |err| {
        std.log.err("error on watching chain height: {}", .{err});
        std.posix.exit(1);
    };
}

test {
    testing.refAllDecls(@This());
}

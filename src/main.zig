const std = @import("std");
const http = std.http;
const testing = std.testing;

const Config = @import("config.zig");
const poller = @import("poller.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");
const worker = @import("worker.zig");

const zpool = @import("zpool");
const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cfg = Config{};

    // Worker setup
    var worker_queue = worker.Queue{ .allocator = allocator };
    const worker_args = worker.Args{ .queue = &worker_queue, .cfg = &cfg };
    const worker_thread = try std.Thread.spawn(.{}, worker.run, .{worker_args});
    defer worker_thread.join();
    defer worker_queue.close(); // this order is important. Since defer are executed LIFO order, the thread only stops when queue is closed so must be called after Thread.join() so it is executed first. Still following? Good boy!

    // Main thread setup
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();
    const uri = try std.Uri.parse(cfg.rpc_url);
    var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    var sqlite_conn = try sqlite.open(cfg.sqlite_db_path);
    // TODO defer close here

    querier.migrations.execute(&sqlite_conn) catch |err| {
        std.log.err("executing migration failed: {}", .{err});
        return;
    };

    var new_poller = poller{ .cfg = &cfg, .client = &jsonrpc_client, .allocator = allocator, .sqlite_conn = &sqlite_conn, .queue = &worker_queue };
    new_poller.watchChainHeight() catch |err| {
        std.log.err("error on watching chain height: {}", .{err});
        std.posix.exit(1);
    };
}

test {
    testing.refAllDecls(@This());
}

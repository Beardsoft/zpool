const std = @import("std");
const http = std.http;
const posix = std.posix;
const testing = std.testing;

const Config = @import("config.zig");
const poller = @import("poller.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");
const Queue = @import("queue.zig");
const worker = @import("worker.zig");

const zpool = @import("zpool");
const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn main() !void {
    if (try std.Thread.getCpuCount() < 2) {
        std.log.err("zpool requires a minimum of 2 cpu cores to run", .{});
        std.posix.exit(1);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cfg = Config{};

    // Worker setup
    var worker_queue = Queue{ .allocator = allocator };
    const worker_args = worker.Args{ .queue = &worker_queue, .cfg = &cfg };
    const worker_thread = try std.Thread.spawn(.{}, worker.run, .{worker_args});
    defer worker_thread.join();
    defer worker_queue.close();

    const sig_handler = posix.Sigaction{ .mask = posix.empty_sigset, .flags = 0, .handler = .{ .handler = Queue.signalHandler } };
    try posix.sigaction(posix.SIG.INT, &sig_handler, null);

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
    };
}

test {
    testing.refAllDecls(@This());
}

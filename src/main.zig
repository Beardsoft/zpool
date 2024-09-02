const std = @import("std");
const http = std.http;

const zpool = @import("zpool");
const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

const poller = @import("./poller.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    // TODO: get this url from config
    const uri = try std.Uri.parse("http://seed1.nimiq.local:8648");

    var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    try poller.pollLatestBlockHeight(&jsonrpc_client);
}

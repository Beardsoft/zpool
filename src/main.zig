const std = @import("std");
const http = std.http;

const zpool = @import("zpool");
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse("https://rpc-testnet.nimiqcloud.com");

    var jsonrpcClient = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    const block_number = try jsonrpcClient.getBlockNumber();

    std.debug.print("Got block number {}", .{block_number});
}

test "zpool lib import" {
    try std.testing.expect(policy.genesis_number == 0);
}

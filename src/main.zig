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

    var cfg = Config{};

    const uri = try std.Uri.parse(cfg.rpc_url);

    var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    try poller.pollLatestBlockHeight(&jsonrpc_client, &cfg);
}

// TODO: this needs to be loaded from somewhere
pub const Config = struct {
    rpc_url: []const u8 = "http://seed1.nimiq.local:8648",
    rpc_username: ?[]const u8 = null,
    rpc_password: ?[]const u8 = null,

    validator_address: []const u8 = "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
    reward_address: []const u8 = "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
};

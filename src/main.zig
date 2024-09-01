const std = @import("std");
const http = std.http;

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

    const uri = try std.Uri.parse("https://rpc-testnet.nimiqcloud.com");

    var jsonrpcClient = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    // TODO: last block should come from database
    var last_block: u64 = 0;
    while (true) {
        const block_number = try jsonrpcClient.getBlockNumber();

        if (last_block == 0) {
            last_block = block_number;
            continue;
        }

        while (last_block < block_number) : (last_block += 1) {
            switch (policy.getBlockTypeByBlockNumber(last_block)) {
                block.BlockType.Checkpoint => {
                    std.log.info("Checkpoint block passed. Block number {d}. Batch number {d}", .{ last_block, policy.getBatchFromBlockNumber(last_block) });
                },
                block.BlockType.Election => {
                    std.log.info("Election block passed. Block number {d}. Batch number {d}", .{ last_block, policy.getBatchFromBlockNumber(last_block) });
                },
                block.BlockType.Micro => {},
            }
        }

        // TODO:
        // we need to upsert the last block number into the database
    }
}

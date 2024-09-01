const std = @import("std");
const zpool = @import("zpool");

const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn pollLatestBlockHeight(client: *jsonrpc.Client) !void {
    // TODO: last block should come from database
    var last_block: u64 = 0;
    while (true) {
        const block_number = try client.getBlockNumber();

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

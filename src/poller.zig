const std = @import("std");
const zpool = @import("zpool");
const main = @import("main.zig");

const block = zpool.block;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

pub fn pollLatestBlockHeight(client: *jsonrpc.Client, cfg: *main.Config) !void {
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
                    try fetchValidatorDetails(client, cfg, last_block);
                },
                block.BlockType.Micro => {},
            }
        }

        // TODO: remove this
        // for now we stop after two epochs. This way the Zig memory debugger
        // can catch any memory leaks we might have after running.
        if (policy.getBatchFromBlockNumber(last_block) > 8) return;

        // TODO:
        // we need to upsert the last block number into the database here
    }
}

fn fetchValidatorDetails(client: *jsonrpc.Client, cfg: *main.Config, current_height: u64) !void {
    const validator = try client.getValidatorByAddress(cfg.validator_address);

    if (!validator.isActive(current_height)) {
        std.log.err("Validator is not active, skipping epoch", .{});
        return;
    }

    std.log.info("Validator is elected. Balance {d}. Num stakers: {d}", .{ validator.balance, validator.numStakers });
}

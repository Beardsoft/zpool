const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @import("config.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");

const zpool = @import("zpool");
const BlockType = zpool.types.BlockType;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

const Self = @This();

client: *jsonrpc.Client,
cfg: *Config,
allocator: Allocator,
sqlite_conn: *sqlite.Conn,

pub fn watchChainHeight(self: *Self) !void {
    // TODO: last block should come from database
    var last_block: u64 = try querier.cursors.getLastPollerHeight(self.sqlite_conn);
    while (true) {
        const block_number = try self.client.getBlockNumber();

        if (last_block == 0) {
            last_block = block_number;
            continue;
        }

        if (block_number == last_block) {
            std.time.sleep(std.time.ns_per_s);
            continue;
        }

        // TODO: this should be ranged in reverse
        // we care about the highest height the most
        while (last_block < block_number) : (last_block += 1) {
            try self.handleNewHeight(last_block);
        }

        querier.cursors.upsertPollerHeight(self.sqlite_conn, last_block) catch |err| {
            std.log.err("failed to upsert height: {}", .{err});
            return err;
        };

        // TODO: remove this
        // for now we stop after two epochs. This way the Zig memory debugger
        // can catch any memory leaks we might have after running.
        if (policy.getBatchFromBlockNumber(last_block) > 8) return;
    }
}

fn handleNewHeight(self: *Self, height: u64) !void {
    switch (policy.getBlockTypeByBlockNumber(height)) {
        BlockType.Checkpoint => {
            std.log.info("Checkpoint block passed. Block number {d}. Batch number {d}", .{ height, policy.getBatchFromBlockNumber(height) });
        },
        BlockType.Election => {
            std.log.info("Election block passed. Block number {d}. Batch number {d}", .{ height, policy.getBatchFromBlockNumber(height) });
            try self.fetchValidatorDetails(height);
        },
        BlockType.Micro => {},
    }
}

fn fetchValidatorDetails(self: *Self, current_height: u64) !void {
    var response = try self.client.getValidatorByAddress(self.cfg.validator_address, self.allocator);
    defer response.deinit();

    // TODO:
    // validate staker contract window here

    const validator = response.result;

    if (!validator.isActive(current_height)) {
        std.log.err("Validator is not active, skipping epoch", .{});
        return;
    }

    std.log.info("Validator is elected. Balance {d}. Num stakers: {d}", .{ validator.balance, validator.numStakers });
    if (validator.numStakers > 0) {
        try self.fetchValidatorStakers(validator.balance);
    }
}

fn fetchValidatorStakers(self: *Self, validator_balance: u64) !void {
    var response = try self.client.getStakersByValidatorAddress(self.cfg.validator_address, self.allocator);
    defer response.deinit();

    // TODO:
    // validate staker contract window here

    for (response.result) |staker| {
        if (staker.balance == 0) continue;

        // TODO:
        // precision may be lost here. We might need to use a more specific type to handle this
        // but we can do that later.
        const stake = @as(f64, @floatFromInt(staker.balance)) * 100 / @as(f64, @floatFromInt(validator_balance));

        std.log.info("Staker with address {s} has stake of {d:.5} with balance {d}", .{ staker.address, stake, staker.balance });
    }
}

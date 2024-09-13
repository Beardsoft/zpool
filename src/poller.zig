const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @import("config.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");
const worker = @import("worker.zig");

const zpool = @import("zpool");
const BlockType = zpool.types.BlockType;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

const Self = @This();

client: *jsonrpc.Client,
cfg: *Config,
allocator: Allocator,
sqlite_conn: *sqlite.Conn,
queue: *worker.Queue,

pub fn watchChainHeight(self: *Self) !void {
    var last_block: u64 = try querier.cursors.getLastPollerHeight(self.sqlite_conn);
    while (true) {
        const block_number = self.client.getBlockNumber() catch |err| {
            std.log.err("error fetching block number: {}", .{err});
            continue;
        };

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
        // for now we stop after 14 batches. This way the Zig memory debugger
        // can catch any memory leaks we might have after running.
        if (policy.getBatchFromBlockNumber(last_block) > 14) {
            std.log.warn("REMOVE ME: early exit after batch 14", .{});
            return;
        }
    }
}

fn handleNewHeight(self: *Self, height: u64) !void {
    switch (policy.getBlockTypeByBlockNumber(height)) {
        BlockType.Checkpoint => {
            std.log.debug("Checkpoint block passed. Block number {d}. Batch number {d}", .{ height, policy.getBatchFromBlockNumber(height) });
            try self.handleCheckpointBlock(height);
        },
        BlockType.Election => {
            std.log.info("Election block passed. Block number {d}. Batch number {d}", .{ height, policy.getBatchFromBlockNumber(height) });
            try self.fetchValidatorDetails(height);
        },
        BlockType.Micro => {}, // TODO: handle last micro block of an epoch,
    }
}

fn handleCheckpointBlock(self: *Self, height: u64) !void {
    const current_collection = policy.getCollectionFromBlockNumber(height);
    if (current_collection == 0) return;

    const next_collection = current_collection + 1;

    if (policy.getCollectionFromBlockNumber(height + 1) == next_collection) {
        std.log.info("a collection has been completed: {d}", .{current_collection});

        const instruction = worker.Instruction{ .instruction_type = worker.InstructionType.Collection, .number = current_collection };
        try self.queue.add(instruction);
    }
}

fn fetchValidatorDetails(self: *Self, current_height: u64) !void {
    // TODO:
    // for genesis validators we have to get the first epoch from the genesis file
    // we may skip this functionality for now since it is an advanced feature.

    const next_epoch_number = policy.getEpochFromBlockNumber(current_height) + 1;
    if (try querier.epochs.epochExists(self.sqlite_conn, next_epoch_number)) {
        std.log.warn("epoch {d} already handled", .{next_epoch_number});
        return;
    }

    var response = try self.client.getValidatorByAddress(self.cfg.validator_address, self.allocator);
    defer response.deinit();

    // TODO:
    // validate staker contract window here

    const validator = response.result;

    if (!validator.isActive(current_height)) {
        std.log.err("Validator is not active, skipping epoch", .{});
        return;
    }

    // TODO:
    // validator status could also be that there are no stakers at all. In which case
    // we don't have to do anything as a pool. We have to introduce a separate status for this.

    std.log.info("Validator is elected. Balance {d}. Num stakers: {d}", .{ validator.balance, validator.numStakers });
    try querier.epochs.insertNewEpoch(self.sqlite_conn, next_epoch_number, validator.numStakers, validator.balance, querier.statuses.Status.InProgress);
    if (validator.numStakers > 0) {
        try self.fetchValidatorStakers(validator.balance, next_epoch_number);
    }
}

fn fetchValidatorStakers(self: *Self, validator_balance: u64, epoch_number: u64) !void {
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
        try querier.stakers.insertNewStaker(self.sqlite_conn, staker.address, epoch_number, staker.balance, stake);
    }
}

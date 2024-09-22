const std = @import("std");
const Allocator = std.mem.Allocator;

const cache = @import("cache.zig");
const config = @import("config.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");
const Queue = @import("queue.zig");

const nimiq = @import("nimiq.zig");
const BlockType = nimiq.types.BlockType;
const jsonrpc = nimiq.jsonrpc;
const policy = nimiq.policy;
const types = nimiq.types;

const Self = @This();

client: *jsonrpc.Client,
cfg: *config.Config,
allocator: Allocator,
sqlite_conn: *sqlite.Conn,
queue: *Queue,

/// This function is the main poller loop. The poller runs on the main
/// thread and is intended for critical path operations. Other operations
/// are executed by the worker instead on a separate thread.
pub fn watchChainHeight(self: *Self) !void {
    var last_block = try querier.cursors.getLastPollerHeight(self.sqlite_conn);
    while (!self.queue.isClosed()) {
        const block_number = self.client.getBlockNumber() catch |err| {
            std.log.err("error fetching block number: {}", .{err});
            continue;
        };

        // TODO: in case of a genesis validator this must be changed
        // to start from genesis number instead of the current height
        if (last_block == 0) {
            last_block = block_number;
            continue;
        }

        if (block_number == last_block) {
            std.time.sleep(std.time.ns_per_s);
            continue;
        }

        // we atomically store the block number so that other threads
        // requiring the latest block number don't have to get this from the
        // node.
        cache.block_number_store(block_number);

        // TODO: this should be ranged in reverse
        // we care about the highest height the most
        while (last_block < block_number) : (last_block += 1) {
            try self.handleNewHeight(last_block);
        }

        querier.cursors.upsertPollerHeight(self.sqlite_conn, last_block) catch |err| {
            std.log.err("failed to upsert height: {}", .{err});
            return err;
        };
    }
}

fn handleNewHeight(self: *Self, height: u32) !void {
    switch (policy.getBlockTypeByBlockNumber(height)) {
        BlockType.Checkpoint => {
            try self.handleCheckpointBlock(height);
        },
        BlockType.Election => {
            std.log.info("Election block passed. Block number {d}. Batch number {d}", .{ height, policy.getBatchFromBlockNumber(height) });
            try self.fetchValidatorDetails(height);
        },
        BlockType.Micro => {}, // TODO: handle last micro block of an epoch,
    }
}

/// this is called for all checkpoint blocks. We bundle batches in collections
/// of multiple batches. Only when a full collection is completed we pass
/// along work to the worker thread to fetch rewards for all batches
/// in the collection.
fn handleCheckpointBlock(self: *Self, height: u32) !void {
    const current_collection = policy.getCollectionFromBlockNumber(height);
    if (current_collection == 0) return;

    const next_collection = current_collection + 1;

    if (policy.getCollectionFromBlockNumber(height + 1) == next_collection) {
        const instruction = Queue.Instruction{ .instruction_type = Queue.InstructionType.Collection, .number = current_collection };
        try self.queue.add(instruction);
    }
}

fn fetchValidatorDetails(self: *Self, current_height: u32) !void {
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
    const validator_status = validator.getStatus(current_height);
    if (validator_status != types.ValidatorStatus.Active) {
        try self.skipValidatorWithInvalidStatus(next_epoch_number, getSchemaStatusFromValidatorStatus(validator_status));
        return;
    }

    if (validator.numStakers == 0) {
        try self.skipValidatorWithInvalidStatus(next_epoch_number, querier.statuses.Status.NoStakers);
        return;
    }

    std.log.info("Validator is elected. Balance {d}. Num stakers: {d}", .{ validator.balance, validator.numStakers });
    try querier.epochs.insertNewEpoch(self.sqlite_conn, next_epoch_number, validator.numStakers, validator.balance, querier.statuses.Status.InProgress);
    try self.fetchValidatorStakers(validator.balance, next_epoch_number);
}

fn getSchemaStatusFromValidatorStatus(status: types.ValidatorStatus) querier.statuses.Status {
    return switch (status) {
        types.ValidatorStatus.Inactive => querier.statuses.Status.InActive,
        types.ValidatorStatus.Retired => querier.statuses.Status.Retired,
        types.ValidatorStatus.Jailed => querier.statuses.Status.Jailed,
        types.ValidatorStatus.Active => querier.statuses.Status.InProgress,
    };
}

fn skipValidatorWithInvalidStatus(self: *Self, epoch_number: u32, status: querier.statuses.Status) !void {
    std.log.info("Skipping epoch {d} with validator status {}", .{ epoch_number, status });
    try querier.epochs.insertNewEpoch(self.sqlite_conn, epoch_number, 0, 0, status);
}

fn fetchValidatorStakers(self: *Self, validator_balance: u64, epoch_number: u32) !void {
    var response = try self.client.getStakersByValidatorAddress(self.cfg.validator_address, self.allocator);
    defer response.deinit();

    // TODO:
    // validate staker contract window here

    for (response.result) |staker| {
        if (staker.balance == 0) continue;

        const stake = @as(f64, @floatFromInt(staker.balance)) * 100 / @as(f64, @floatFromInt(validator_balance));

        std.log.info("Staker with address {s} has stake of {d:.5} with balance {d}", .{ staker.address, stake, staker.balance });
        try querier.stakers.insertNewStaker(self.sqlite_conn, staker.address, epoch_number, staker.balance, stake);
    }
}

const std = @import("std");
const math = std.math;
const testing = std.testing;

const policy = @import("policy");

const BlockType = @import("types.zig").BlockType;

pub const genesis_number = policy.genesis_number;
pub const batch_size = policy.batch_size;
pub const epoch_size = policy.epoch_size;
pub const batches_per_epoch = policy.batches_per_epoch;
pub const collection_batches = policy.collection_batches;
pub const collection_size = policy.collection_size;
pub const collections_per_epoch = policy.collections_per_epoch;
pub const network_id: u8 = policy.network_id;
pub const jail_period = epoch_size * 8;

// This is to verify the policy values are correct.
// considering we can compile different constants based on Dpolicy flag
// we cannot cover this during unit tests alone.
comptime {
    if (std.debug.runtime_safety) {
        std.debug.assert(collection_batches * batch_size == collection_size);
        std.debug.assert(collection_size * collections_per_epoch == epoch_size);
        std.debug.assert(batch_size * batches_per_epoch == epoch_size);
    }
}

/// Returns the block number for the given batch number
pub fn getBlockNumberForBatch(batch_number: u32) u32 {
    return batch_number * batch_size + genesis_number;
}

/// Returns the block number for the given epoch number
pub fn getBlockNumberForEpoch(epoch_number: u32) u32 {
    return epoch_number * epoch_size + genesis_number;
}

/// Returns the batch number for the given block number
pub fn getBatchFromBlockNumber(block_number: u32) u32 {
    return calculateSizeForBlock(block_number, batch_size);
}

/// Returns the collections number for the given block number
pub fn getCollectionFromBlockNumber(block_number: u32) u32 {
    if (block_number < batch_size) return 0;
    return calculateSizeForBlock(block_number - batch_size, collection_size);
}

/// Returns the collection number for he given batch number
pub fn getCollectionFromBatchNumber(batch_number: u32) u32 {
    return getCollectionFromBlockNumber(getBlockNumberForBatch(batch_number));
}

/// Returns the first batch number part of the given collection number
pub fn getFirstBatchFromCollection(collection_number: u32) u32 {
    const block_number = ((collection_number - 1) * collection_size) + batch_size + 1 + genesis_number;
    return getBatchFromBlockNumber(block_number);
}

/// Returns the epoch number for the given batch number
pub fn getEpochFromBatchNumber(batch_number: u32) u32 {
    return calculateSizeForBlock(getBlockNumberForBatch(batch_number), epoch_size);
}

/// Returns the epoch number for the given block number
pub fn getEpochFromBlockNumber(block_number: u32) u32 {
    return calculateSizeForBlock(block_number, epoch_size);
}

fn calculateSizeForBlock(block_number: u32, size: comptime_int) u32 {
    const number = block_number - genesis_number;
    return @intFromFloat(math.ceil(@as(f64, @floatFromInt(number)) / size));
}

/// Returns the block type for the given block number
pub fn getBlockTypeByBlockNumber(block_number: u32) BlockType {
    const number = block_number - genesis_number;

    if (@rem(number, batch_size) == 0 and @rem(number, epoch_size) == 0) {
        return BlockType.Election;
    }

    if (@rem(number, batch_size) == 0) {
        return BlockType.Checkpoint;
    }

    return BlockType.Micro;
}

/// Returns whether one or macro blocks has passed since original block height, compared to
/// current block height. Macro blocks provide finality on chain, so once a macro block has passed
/// original height can be considered final / confirmed.
pub fn macroBlockPassedSince(original_block: u32, current_block: u32) bool {
    return getBatchFromBlockNumber(current_block) > getBatchFromBlockNumber(original_block);
}

test "policy unittest constants" {
    try testing.expect(genesis_number == 0);
    try testing.expect(batch_size == 60);
    try testing.expect(epoch_size == 43200);
    try testing.expect(batches_per_epoch == 720);
}

test "block number for batch number" {
    try testing.expect(getBlockNumberForBatch(2) == 120 + genesis_number);
}

test "block number for epoch number" {
    try testing.expect(getBlockNumberForEpoch(1) == 43200 + genesis_number);
}

test "get epoch from batch number" {
    try testing.expect(getEpochFromBatchNumber(721) == 2);
}

test "get collection from block number" {
    try testing.expect(getCollectionFromBlockNumber(60) == 0);
    try testing.expect(getCollectionFromBlockNumber(120) == 1);
    try testing.expect(getFirstBatchFromCollection(1) == 2);
    try testing.expect(getFirstBatchFromCollection(2) == 62);
}

test "block types by block number" {
    try testing.expect(getBlockTypeByBlockNumber(60) == BlockType.Checkpoint);
    try testing.expect(getBlockTypeByBlockNumber(43200) == BlockType.Election);
    try testing.expect(getBlockTypeByBlockNumber(999) == BlockType.Micro);
}

test "macro block passed since" {
    try testing.expect(!macroBlockPassedSince(70, 71));
    try testing.expect(macroBlockPassedSince(110, 163));
}

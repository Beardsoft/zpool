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
pub const network_id: u8 = policy.network_id;

pub fn getBlockNumberForBatch(batch_number: u32) u32 {
    return batch_number * batch_size + genesis_number;
}

pub fn getBlockNumberForEpoch(epoch_number: u32) u32 {
    return epoch_number * epoch_size + genesis_number;
}

pub fn getBatchFromBlockNumber(block_number: u32) u32 {
    return calculateSizeForBlock(block_number, batch_size);
}

pub fn getCollectionFromBlockNumber(block_number: u32) u32 {
    if (block_number < batch_size) return 0;
    return calculateSizeForBlock(block_number - batch_size, collection_size);
}

pub fn getCollectionFromBatchNumber(batch_number: u32) u32 {
    return getCollectionFromBlockNumber(getBlockNumberForBatch(batch_number));
}

pub fn getFirstBatchFromCollection(collection_number: u32) u32 {
    const block_number = ((collection_number - 1) * collection_size) + batch_size + 1 + genesis_number;
    return getBatchFromBlockNumber(block_number);
}

pub fn getEpochFromBatchNumber(batch_number: u32) u32 {
    return calculateSizeForBlock(getBlockNumberForBatch(batch_number), epoch_size);
}

pub fn getEpochFromBlockNumber(block_number: u32) u32 {
    return calculateSizeForBlock(block_number, epoch_size);
}

fn calculateSizeForBlock(block_number: u32, size: comptime_int) u32 {
    const number = block_number - genesis_number;
    return @intFromFloat(math.ceil(@as(f64, @floatFromInt(number)) / size));
}

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
    try testing.expect(getFirstBatchFromCollection(2) == 242);
}

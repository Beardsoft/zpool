const std = @import("std");
const math = std.math;
const testing = std.testing;

const policy = @import("policy");

const BlockType = @import("types.zig").BlockType;

pub const genesis_number = policy.genesis_number;
pub const batch_size = policy.batch_size;
pub const epoch_size = policy.epoch_size;
pub const batches_per_epoch = policy.batches_per_epoch;

pub fn getBlockNumberForBatch(batch_number: u64) u64 {
    return batch_number * batch_size + genesis_number;
}

pub fn getBlockNumberForEpoch(epoch_number: u64) u64 {
    return epoch_number * epoch_size + genesis_number;
}

pub fn getBatchFromBlockNumber(block_number: u64) u64 {
    return calculateSizeForBlock(block_number, batch_size);
}

pub fn getEpochFromBatchNumber(batch_number: u64) u64 {
    return calculateSizeForBlock(getBlockNumberForBatch(batch_number), epoch_size);
}

fn calculateSizeForBlock(block_number: u64, size: comptime_int) u64 {
    const number = block_number - genesis_number;
    return @intFromFloat(math.ceil(@as(f64, @floatFromInt(number)) / size));
}

pub fn getBlockTypeByBlockNumber(block_number: u64) BlockType {
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

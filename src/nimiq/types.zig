const std = @import("std");
const Allocator = std.mem.Allocator;
const policy = @import("policy.zig");
const testing = std.testing;

pub const AccountType = enum(u8) { Basic, Vesting, HTLC, Staking };

pub const BlockType = enum { Election, Checkpoint, Micro };

pub const TransactionType = enum(u8) { Basic, Extended };

pub const Transaction = struct {
    const Self = @This();

    blockNumber: u32,
    executionResult: bool,

    pub fn isConfirmed(self: Self, current_height: u32) bool {
        return policy.macroBlockPassedSince(self.blockNumber, current_height);
    }
};

pub const Inherent = struct {
    const Self = @This();
    type: []u8,
    blockNumber: u32,
    validatorAddress: ?[]u8 = null,
    target: ?[]u8 = null,
    value: ?u64 = null,

    pub fn isReward(self: Self) bool {
        if (self.type.len == 6) {
            return (self.type[0] == 'r' and self.type[1] == 'e' and self.type[2] == 'w' and self.type[3] == 'a' and self.type[4] == 'r' and self.type[5] == 'd');
        }

        return false;
    }

    pub fn cloneArenaAlloc(self: Self, allocator: Allocator) !Self {
        const new_type = try allocator.alloc(u8, self.type.len);
        @memcpy(new_type, self.type);

        var new_inherent = Self{ .type = new_type, .blockNumber = self.blockNumber, .value = self.value };

        if (self.validatorAddress) |validator_address| {
            const new_address = try allocator.alloc(u8, validator_address.len);
            @memcpy(new_address, validator_address);
            new_inherent.validatorAddress = new_address;
        }

        if (self.target) |target_address| {
            const new_address = try allocator.alloc(u8, target_address.len);
            @memcpy(new_address, target_address);
            new_inherent.target = new_address;
        }

        return new_inherent;
    }
};

test "inherent is reward" {
    const allocator = testing.allocator;
    const reward = try allocator.alloc(u8, 6);
    defer allocator.free(reward);
    reward[0] = 'r';
    reward[1] = 'e';
    reward[2] = 'w';
    reward[3] = 'a';
    reward[4] = 'r';
    reward[5] = 'd';

    const test_inherent = Inherent{ .type = reward, .blockNumber = 120 };
    try testing.expect(test_inherent.isReward());
}

/// Denotes a staker on the Nimiq network
pub const Staker = struct {
    const Self = @This();

    address: []u8,
    delegation: []u8,
    balance: u64,
    inactiveBalance: u64,
    retiredBalance: u64,
    inactiveFrom: ?u64 = null,

    pub fn cloneArenaAlloc(self: Self, allocator: Allocator) !Self {
        const new_address = try allocator.alloc(u8, self.address.len);
        @memcpy(new_address, self.address);

        const new_delegation = try allocator.alloc(u8, self.delegation.len);
        @memcpy(new_delegation, self.delegation);

        return Self{
            .address = new_address,
            .delegation = new_delegation,
            .balance = self.balance,
            .inactiveBalance = self.inactiveBalance,
            .retiredBalance = self.retiredBalance,
            .inactiveFrom = self.inactiveFrom,
        };
    }
};

pub const ValidatorStatus = enum {
    Active,
    Inactive,
    Jailed,
    Retired,
};

/// Denotes a validator on the Nimiq network
pub const Validator = struct {
    const Self = @This();

    address: []u8,
    rewardAddress: []u8,
    balance: u64,
    numStakers: u16,
    retired: bool,
    inactivityFlag: ?u32 = null,
    jailedFrom: ?u32 = null,

    pub fn cloneArenaAlloc(self: Self, allocator: Allocator) !Self {
        const new_address = try allocator.alloc(u8, self.address.len);
        @memcpy(new_address, self.address);

        const new_reward_address = try allocator.alloc(u8, self.rewardAddress.len);
        @memcpy(new_reward_address, self.rewardAddress);

        return Self{
            .address = new_address,
            .rewardAddress = new_reward_address,
            .balance = self.balance,
            .numStakers = self.numStakers,
            .retired = self.retired,
            .inactivityFlag = self.inactivityFlag,
            .jailedFrom = self.jailedFrom,
        };
    }

    /// Returns if the validator is active
    pub fn isActive(self: Self, current_height: u32) bool {
        return self.getStatus(current_height) == ValidatorStatus.Active;
    }

    /// Returns the status of the validator. Returns:
    /// `ValidatorStatus.Inactive` if inactivityFlag is lower than current height
    /// `ValidatorStatus.Jailed` if jailedFrom is lower than current height
    /// `ValidatorStatus.Active` in all other cases.
    pub fn getStatus(self: Self, current_height: u32) ValidatorStatus {
        if (self.retired) return ValidatorStatus.Retired;

        if (self.inactivityFlag) |height| {
            if (height > current_height) {
                return ValidatorStatus.Inactive;
            }
        }

        if (self.jailedFrom) |height| {
            if (height > current_height) {
                return ValidatorStatus.Jailed;
            }
        }

        return ValidatorStatus.Active;
    }
};

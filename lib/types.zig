/// Denotes a staker on the Nimiq network
pub const Staker = struct {
    address: []u8,
    delegation: []u8,
    balance: u64,
    inactiveBalance: u64,
    retiredBalance: u64,
    inactiveFrom: ?u64 = null,
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
    numStakers: u64,
    retired: bool,
    inactivityFlag: ?u64 = null,
    jailedFrom: ?u64 = null,

    /// Returns if the validator is active
    pub fn isActive(self: Self, current_height: u64) bool {
        return self.getStatus(current_height) == ValidatorStatus.Active;
    }

    /// Returns the status of the validator. Returns:
    /// `ValidatorStatus.Inactive` if inactivityFlag is lower than current height
    /// `ValidatorStatus.Jailed` if jailedFrom is lower than current height
    /// `ValidatorStatus.Active` in all other cases.
    pub fn getStatus(self: Self, current_height: u64) ValidatorStatus {
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

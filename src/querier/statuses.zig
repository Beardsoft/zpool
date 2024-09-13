const std = @import("std");
const testing = std.testing;

pub const Status = enum(u8) {
    const Self = @This();

    NotElected,
    InProgress,
    Retired,
    InActive,
    Error,
    Completed,
    Pending,
    OutForPayment,

    pub fn isInvalid(self: Self) bool {
        return (self == Status.NotElected or self == Status.Retired or self == Status.InActive or self == Status.Error);
    }
};

test "status is invalid" {
    try testing.expect(Status.NotElected.isInvalid());
    try testing.expect(Status.Retired.isInvalid());
    try testing.expect(Status.InActive.isInvalid());
    try testing.expect(Status.Error.isInvalid());

    try testing.expect(!Status.InProgress.isInvalid());
}

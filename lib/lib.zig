const std = @import("std");
const testing = std.testing;

pub const jsonrpc = @import("jsonrpc.zig");

test {
    testing.refAllDecls(@This());
}

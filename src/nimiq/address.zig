const std = @import("std");
const base32 = @import("base32");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const nimiq_base32_alphabet = "0123456789ABCDEFGHJKLMNPQRSTUVXY";
const nimiq_base32_encoder = base32.Encoding.initWithPadding(nimiq_base32_alphabet, null);

pub const InvalidAddressError = error{
    InvalidLength,
    InvalidCountryCode,
};

const address_length = 20;
const address_length_hex = address_length * 2;
const address_length_friendly = 44;

pub const StakingContractAddress = Self{ .bytes = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 } };

const Self = @This();

/// Address holds the raw bytes of a Nimiq address
/// the address can either be parsed from hex or the friendly address format
bytes: [address_length]u8 = undefined,

/// Parse address from hex string
pub fn parseAddressFromHex(self: *Self, hex: []const u8) !void {
    if (hex.len != address_length_hex) return InvalidAddressError.InvalidLength;

    const decoded = try fmt.hexToBytes(&self.bytes, hex);
    if (decoded.len != address_length) return InvalidAddressError.InvalidLength;

    self.bytes = decoded[0..address_length].*;
}

/// Parse address from friendly address format
pub fn parseAddressFromFriendly(self: *Self, friendly: []const u8) !void {
    if (friendly.len != address_length_friendly) return InvalidAddressError.InvalidLength;
    if (friendly[0] != 'N' or friendly[1] != 'Q') return InvalidAddressError.InvalidCountryCode;

    var trimmed = [_]u8{0} ** 32;
    var index: usize = 0;
    for (friendly[5..]) |
        char,
    | {
        if (char == ' ') continue;
        trimmed[index] = char;
        index += 1;
    }

    var out = try nimiq_base32_encoder.decode(&self.bytes, &trimmed);
    self.bytes = out[0..address_length].*;
}

var test_address = Self{ .bytes = [20]u8{ 0x93, 0xef, 0x3e, 0x94, 0x5f, 0x99, 0xcf, 0x64, 0x3f, 0x26, 0xa2, 0x58, 0xa2, 0x88, 0x32, 0xf8, 0x98, 0xed, 0xa4, 0x96 } };

test "Parse address from hex: invalid length" {
    var address = Self{};
    const result = address.parseAddressFromHex("0016");
    try testing.expectError(InvalidAddressError.InvalidLength, result);
}

test "Parse address from hex: ok" {
    const allocator = testing.allocator;

    var address = try allocator.create(Self);
    defer allocator.destroy(address);

    try address.parseAddressFromHex("93ef3e945f99cf643f26a258a28832f898eda496");
    try testing.expectEqualSlices(u8, &address.bytes, &test_address.bytes);
}

test "Parse address from friendly: invalid length" {
    const allocator = testing.allocator;

    var address = try allocator.create(Self);
    defer allocator.destroy(address);

    const result = address.parseAddressFromFriendly("0016");
    try testing.expectError(InvalidAddressError.InvalidLength, result);
}

test "Parse address from friendly: invalid country code" {
    const allocator = testing.allocator;

    var address = try allocator.create(Self);
    defer allocator.destroy(address);

    const result = address.parseAddressFromFriendly("NT61 JFPK V52Y K77N 8FR6 L9CA 521J Y2CE T94N");
    try testing.expectError(InvalidAddressError.InvalidCountryCode, result);
}

test "Parse address from friendly: ok" {
    const allocator = testing.allocator;

    var address = try allocator.create(Self);
    defer allocator.destroy(address);

    try address.parseAddressFromFriendly("NQ61 JFPK V52Y K77N 8FR6 L9CA 521J Y2CE T94N");
    try testing.expectEqualSlices(u8, &address.bytes, &test_address.bytes);
}

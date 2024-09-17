const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;

const Address = @import("address.zig");

pub fn pushByte(list: *std.ArrayList(u8), byte: u8) Allocator.Error!void {
    return list.append(byte);
}

pub fn pushAddress(list: *std.ArrayList(u8), address: Address) Allocator.Error!void {
    return list.appendSlice(&address.bytes);
}

pub fn pushBytes(list: *std.ArrayList(u8), bytes: []u8) Allocator.Error!void {
    return list.appendSlice(bytes);
}

pub fn pushU16BigEndian(list: *std.ArrayList(u8), num: u16) Allocator.Error!void {
    var enc = [_]u8{0} ** 2;
    std.mem.writeInt(u16, &enc, num, std.builtin.Endian.big);
    return list.appendSlice(enc[0..]);
}

pub fn pushU32BigEndian(list: *std.ArrayList(u8), num: u32) Allocator.Error!void {
    var enc = [_]u8{0} ** 4;
    std.mem.writeInt(u32, &enc, num, std.builtin.Endian.big);
    return list.appendSlice(enc[0..]);
}

pub fn pushU64BigEndian(list: *std.ArrayList(u8), num: u64) Allocator.Error!void {
    var enc = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &enc, num, std.builtin.Endian.big);
    return list.appendSlice(enc[0..]);
}

pub fn pushVarInt(list: *std.ArrayList(u8), num: usize) !void {
    try std.leb.writeULEB128(list.writer(), num);
}

test "Serialize address" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushAddress(&array_list, Address.StakingContractAddress);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    try testing.expectEqualSlices(u8, Address.StakingContractAddress.bytes[0..], result);
}

test "Serialize u16 10" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU16BigEndian(&array_list, 10);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 0, 10 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize u16 257" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU16BigEndian(&array_list, 257);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 1, 1 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize u32 10" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU32BigEndian(&array_list, 10);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 0, 0, 0, 10 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize u32 320985" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU32BigEndian(&array_list, 320985);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 0, 4, 229, 217 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize u64 10" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU64BigEndian(&array_list, 10);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 10 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize u64 20389753886409" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushU64BigEndian(&array_list, 20389753886409);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 0, 0, 18, 139, 92, 9, 150, 201 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

test "Serialize varint 293478" {
    const allocator = testing.allocator;
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();

    try pushVarInt(&array_list, 293478);
    const result = try array_list.toOwnedSlice();
    defer allocator.free(result);

    const expected = [_]u8{ 230, 244, 17 };
    try testing.expectEqualSlices(u8, expected[0..], result);
}

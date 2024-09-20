const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Ed25519 = std.crypto.sign.Ed25519;

const Address = @import("address.zig");
const policy = @import("policy.zig");
const serializer = @import("serializer.zig");
const types = @import("types.zig");

pub const BuilderError = error{
    InsufficientFunds,
    ValueCannotBeZero,
};

pub const Builder = struct {
    const Self = @This();

    arena: ?ArenaAllocator,
    transaction_type: types.TransactionType = types.TransactionType.Basic,
    sender: Address,
    sender_type: types.AccountType = types.AccountType.Basic,
    sender_data: ?[]u8 = null,
    recipient: Address,
    recipient_type: types.AccountType = types.AccountType.Basic,
    recipient_data: ?[]u8 = null,
    value: u64,
    fee: u64 = 0,
    validity_start_height: u32,
    network_id: u8 = 0,
    flags: u8 = 0,
    proof: ?[]u8 = null,

    pub fn deinit(self: *Self) void {
        if (self.arena) |arena| {
            arena.deinit();
        }
    }

    pub fn newBasic(sender: Address, recipient: Address, value: u64, validity_start_height: u32) !Self {
        if (value == 0) return BuilderError.ValueCannotBeZero;

        return .{
            .sender = sender,
            .recipient = recipient,
            .value = value,
            .validity_start_height = validity_start_height,
            .network_id = policy.network_id,
        };
    }

    pub fn newAddStake(allocator: Allocator, sender: Address, recipient: Address, value: u64, validity_start_height: u32) !Self {
        if (value == 0) return BuilderError.ValueCannotBeZero;

        var arena = ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();

        var list = std.ArrayList(u8).init(arena_allocator);
        try serializer.pushByte(&list, 6);
        try serializer.pushAddress(&list, recipient);

        const recipient_data = try list.toOwnedSlice();

        return .{
            .arena = arena,
            .transaction_type = types.TransactionType.Extended,
            .sender = sender,
            .recipient = Address.StakingContractAddress,
            .recipient_type = types.AccountType.Staking,
            .recipient_data = recipient_data,
            .value = value,
            .validity_start_height = validity_start_height,
            .network_id = policy.network_id,
        };
    }

    pub fn setFeeByByteSize(self: *Self) !void {
        switch (self.transaction_type) {
            types.TransactionType.Basic => {
                self.fee = 3 + 64 + 32 + 20 + 8 + 8 + 4;
            },
            types.TransactionType.Extended => {
                var fee: u64 = 3 + 24 + 24 + 98 + 8 + 8 + 4;
                if (self.recipient_data) |recipient_data| {
                    fee += @intCast(recipient_data.len);
                }

                if (self.sender_data) |sender_data| {
                    fee += @intCast(sender_data.len);
                }

                self.fee = fee;
            },
        }

        if (self.value < self.fee) return BuilderError.InsufficientFunds;
        self.value -= self.fee;
    }

    pub fn signAndCompile(self: *Self, allocator: Allocator, key_pair: Ed25519.KeyPair) ![]u8 {
        const signature_payload = try self.createSigningPayload(allocator);
        defer allocator.free(signature_payload);

        const signature = try key_pair.sign(signature_payload, null);
        var signature_bytes = signature.toBytes();

        switch (self.transaction_type) {
            types.TransactionType.Basic => return self.compileBasicTransaction(allocator, key_pair.public_key, signature_bytes[0..]),
            types.TransactionType.Extended => return self.compileExtendedTransaction(allocator, key_pair.public_key, signature_bytes[0..]),
        }
    }

    fn createSigningPayload(self: *Self, allocator: Allocator) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);

        if (self.recipient_data) |recipient_data| {
            try serializer.pushU16BigEndian(&list, @as(u16, @intCast(recipient_data.len)));
            try serializer.pushBytes(&list, recipient_data);
        } else {
            try serializer.pushU16BigEndian(&list, 0);
        }

        try serializer.pushAddress(&list, self.sender);
        try serializer.pushByte(&list, @intFromEnum(self.sender_type));
        try serializer.pushAddress(&list, self.recipient);
        try serializer.pushByte(&list, @intFromEnum(self.recipient_type));
        try serializer.pushU64BigEndian(&list, self.value);
        try serializer.pushU64BigEndian(&list, self.fee);
        try serializer.pushU32BigEndian(&list, self.validity_start_height);
        try serializer.pushByte(&list, self.network_id);
        try serializer.pushByte(&list, self.flags);

        if (self.sender_data) |sender_data| {
            try serializer.pushVarInt(&list, @as(u16, @intCast(sender_data.len)));
            try serializer.pushBytes(&list, sender_data);
        } else {
            try serializer.pushVarInt(&list, 0);
        }

        return list.toOwnedSlice();
    }

    fn compileBasicTransaction(self: *Self, allocator: Allocator, public_key: Ed25519.PublicKey, signature: []u8) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        var public_key_bytes = public_key.toBytes();

        try serializer.pushByte(&list, @intFromEnum(self.transaction_type));
        try serializer.pushByte(&list, 0); // signature type, always Ed25519
        try serializer.pushBytes(&list, public_key_bytes[0..]);
        try serializer.pushAddress(&list, self.recipient);
        try serializer.pushU64BigEndian(&list, self.value);
        try serializer.pushU64BigEndian(&list, self.fee);
        try serializer.pushU32BigEndian(&list, self.validity_start_height);
        try serializer.pushByte(&list, self.network_id);
        try serializer.pushBytes(&list, signature);

        const raw_tx = try list.toOwnedSlice();
        defer allocator.free(raw_tx);

        var raw_tx_hex = try allocator.alloc(u8, raw_tx.len * 2);
        raw_tx_hex = bytesToHex(raw_tx_hex, raw_tx);
        return raw_tx_hex;
    }

    fn compileExtendedTransaction(self: *Self, allocator: Allocator, public_key: Ed25519.PublicKey, signature: []u8) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);
        const proof = try createProof(allocator, public_key, signature);
        defer allocator.free(proof);

        try serializer.pushByte(&list, @intFromEnum(self.transaction_type));
        try serializer.pushAddress(&list, self.sender);
        try serializer.pushByte(&list, @intFromEnum(self.sender_type));

        if (self.sender_data) |sender_data| {
            try serializer.pushVarInt(&list, @as(u16, @intCast(sender_data.len)));
            try serializer.pushBytes(&list, sender_data);
        } else {
            try serializer.pushVarInt(&list, 0);
        }

        try serializer.pushAddress(&list, self.recipient);
        try serializer.pushByte(&list, @intFromEnum(self.recipient_type));

        if (self.recipient_data) |recipient_data| {
            try serializer.pushVarInt(&list, @as(u16, @intCast(recipient_data.len)));
            try serializer.pushBytes(&list, recipient_data);
        } else {
            try serializer.pushVarInt(&list, 0);
        }

        try serializer.pushU64BigEndian(&list, self.value);
        try serializer.pushU64BigEndian(&list, self.fee);
        try serializer.pushU32BigEndian(&list, self.validity_start_height);
        try serializer.pushByte(&list, self.network_id);
        try serializer.pushByte(&list, self.flags);

        try serializer.pushVarInt(&list, @as(u16, @intCast(proof.len)));
        try serializer.pushBytes(&list, proof);

        const raw_tx = try list.toOwnedSlice();
        defer allocator.free(raw_tx);

        var raw_tx_hex = try allocator.alloc(u8, raw_tx.len * 2);
        raw_tx_hex = bytesToHex(raw_tx_hex, raw_tx);
        return raw_tx_hex;
    }

    fn createProof(allocator: Allocator, public_key: Ed25519.PublicKey, signature: []u8) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);

        var public_key_bytes = public_key.toBytes();

        try serializer.pushByte(&list, 0);
        try serializer.pushBytes(&list, public_key_bytes[0..]);
        try serializer.pushByte(&list, 0);
        try serializer.pushBytes(&list, signature);

        return list.toOwnedSlice();
    }

    fn bytesToHex(result: []u8, input: []u8) []u8 {
        const charset = "0123456789abcdef";
        for (input, 0..) |b, i| {
            result[i * 2 + 0] = charset[b >> 4];
            result[i * 2 + 1] = charset[b & 15];
        }
        return result;
    }
};

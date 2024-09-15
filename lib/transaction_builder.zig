const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

const Address = @import("address.zig");
const policy = @import("policy.zig");
const serializer = @import("serializer.zig");
const types = @import("types.zig");

pub const Builder = struct {
    const Self = @This();

    allocator: Allocator,
    transaction_type: types.TransactionType = types.TransactionType.Basic,
    sender: Address,
    sender_type: types.AccountType,
    sender_data: ?[]u8 = null,
    recipient: Address,
    recipient_type: types.AccountType,
    recipient_data: ?[]u8 = null,
    value: u64,
    fee: u64 = 0,
    validity_start_height: u32,
    network_id: u8 = 0,
    flags: u8 = 0,
    proof: ?[]u8 = null,

    pub fn newBasic(allocator: Allocator, sender: Address, recipient: Address, value: u64, validity_start_height: u32) Self {
        return .{
            .allocator = allocator,
            .sender = sender,
            .sender_type = types.AccountType.Basic,
            .recipient = recipient,
            .recipient_type = types.AccountType.Basic,
            .value = value,
            .validity_start_height = validity_start_height,
            .network_id = policy.network_id,
        };
    }

    pub fn setFeeByByteSize(self: *Self) void {
        switch (self.transaction_type) {
            types.TransactionType.Basic => {
                self.fee = 3 + 64 + 32 + 20 + 8 + 8 + 4;
            },
            types.TransactionType.Extended => {
                var fee = 3 + 24 + 24 + 98 + 8 + 8 + 4;
                if (self.recipient_data) |recipient_data| {
                    fee += recipient_data.len;
                }

                if (self.sender_data) |sender_data| {
                    fee += sender_data.len;
                }

                self.fee = fee;
            },
        }
    }

    pub fn signAndCompile(self: *Self, allocator: Allocator, key_pair: Ed25519.KeyPair) ![]u8 {
        const signature_payload = try self.createSigningPayload(allocator);
        defer allocator.free(signature_payload);

        const signature = try key_pair.sign(signature_payload, null);
        const signature_bytes = signature.toBytes();

        switch (self.transaction_type) {
            types.TransactionType.Basic => self.compileBasicTransaction(allocator, key_pair.public_key, signature_bytes[0..]),
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
            try serializer.pushU16BigEndian(&list, 0);
        }

        return list.toOwnedSlice();
    }

    fn compileBasicTransaction(self: *Self, allocator: Allocator, public_key: Ed25519.PublicKey, signature: []u8) ![]u8 {
        var list = std.ArrayList(u8).init(allocator);

        try serializer.pushByte(&list, self.transaction_type);
        try serializer.pushByte(&list, 0); // signature type, always Ed25519
        try serializer.pushBytes(&list, public_key.toBytes()[0..]);
        try serializer.pushAddress(&list, self.recipient);
        try serializer.pushU64BigEndian(&list, self.value);
        try serializer.pushU64BigEndian(&list, self.fee);
        try serializer.pushU32BigEndian(&list, self.validity_start_height);
        try serializer.pushByte(&list, self.network_id);
        try serializer.pushBytes(&list, signature);

        const raw_tx = try list.toOwnedSlice();
        defer allocator.free(raw_tx);

        const raw_tx_hex = try allocator.alloc(u8, raw_tx.len * 2);

        try std.fmt.hexToBytes(&raw_tx_hex, raw_tx);
        return raw_tx_hex;
    }
};

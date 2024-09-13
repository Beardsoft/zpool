const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const http = std.http;
const json = std.json;
const testing = std.testing;
const Uri = std.Uri;

const types = @import("types.zig");

pub const Error = error{
    ParseError,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    ServerError,
    UnknownError,
    UnexpectedHttpStatus,
};

/// Create a new JSON-RPC request type
/// that can instantiate the desired request
/// with the right parameter typing
pub fn Request(comptime T: type) type {
    return struct {
        const Self = @This();

        jsonrpc: []const u8 = "2.0",
        id: u64 = 1,
        method: []const u8,
        params: T = undefined,

        pub fn marshalJSON(self: *Self, allocator: Allocator) ![]u8 {
            return json.stringifyAlloc(allocator, self, .{});
        }
    };
}

/// Create a new JSON-RPC response type
/// that can instantiate the desired respone
/// with the right result typing
pub fn Response(comptime T: type) type {
    return struct {
        const Self = @This();

        result: ?struct { data: T, metadata: ?struct {
            blockNumber: u64,
            blockHash: []const u8,
        } = null } = null,
        @"error": ?ResponseError = null,
    };
}

/// Envelope is a wrapper around a type
/// includes the `block_number` from metadata if available
/// The wrapped type is allocated using an ArenaAllocator
/// after usage of the wrapped type call deinit() to free memory.
pub fn Envelope(comptime T: type) type {
    return struct {
        const Self = @This();

        result: T,
        block_number: ?u64,
        arena: ?ArenaAllocator = null,

        pub fn deinit(self: *Self) void {
            if (self.arena) |allocator| {
                allocator.deinit();
            }
        }
    };
}

const ResponseError = struct {
    code: i32,
    message: []u8,
    // we omit data field for now
    // data: []u8,
};

/// Exposes JSON-RPC client for the Nimiq blockchain
/// provides generic functionality to send any request
/// and specific method implementations for commonly used
/// functionality
pub const Client = struct {
    const Self = @This();

    // TODO: in case of auth we have to handle bearer token based of username and password
    allocator: Allocator,
    client: *http.Client,
    uri: Uri,

    /// `getBlockNumber` returns the current block height of the chain
    pub fn getBlockNumber(self: *Self) !u64 {
        const params = try self.allocator.alloc(bool, 0);
        defer self.allocator.free(params);

        const ReqType = Request([]bool);
        var req = ReqType{ .method = "getBlockNumber", .params = params };

        const ResponseType = Response(u64);
        const parsed = try self.send(&req, ResponseType);
        defer parsed.deinit();

        return parsed.value.result.?.data;
    }

    /// `getValidatorByAddress` returns the given validator by address
    pub fn getValidatorByAddress(self: *Self, address: []const u8, allocator: Allocator) !Envelope(types.Validator) {
        const ReqType = Request([][]const u8);
        const params = try self.allocator.alloc([]const u8, 1);
        defer self.allocator.free(params);

        params[0] = address;
        var req = ReqType{ .method = "getValidatorByAddress", .params = params };

        const ResponseType = Response(types.Validator);
        const parsed = try self.send(&req, ResponseType);
        defer parsed.deinit();

        var arena = ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        const new_validator = try parsed.value.result.?.data.cloneArenaAlloc(arena_allocator);

        const EnvelopeType = Envelope(types.Validator);
        const block_number: ?u64 = if (parsed.value.result.?.metadata) |meta| meta.blockNumber else null;
        return EnvelopeType{ .block_number = block_number, .result = new_validator, .arena = arena };
    }

    /// `getStakersByValidatorAddress` returns the stakers for the given validator
    pub fn getStakersByValidatorAddress(self: *Self, address: []const u8, allocator: Allocator) !Envelope([]types.Staker) {
        const ReqType = Request([][]const u8);
        const params = try self.allocator.alloc([]const u8, 1);
        defer self.allocator.free(params);

        params[0] = address;
        var req = ReqType{ .method = "getStakersByValidatorAddress", .params = params };

        const ResponseType = Response([]types.Staker);
        const parsed = try self.send(&req, ResponseType);
        defer parsed.deinit();

        var arena = ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        const stakers = try arena_allocator.alloc(types.Staker, parsed.value.result.?.data.len);
        for (parsed.value.result.?.data, 0..) |staker, index| {
            const cloned = try staker.cloneArenaAlloc(arena_allocator);
            stakers[index] = cloned;
        }

        const EnvelopeType = Envelope([]types.Staker);
        const block_number: ?u64 = if (parsed.value.result.?.metadata) |meta| meta.blockNumber else null;
        return EnvelopeType{ .block_number = block_number, .result = stakers, .arena = arena };
    }

    /// `getInherentsByBlockNumber` returns the inherents for the given block number
    pub fn getInherentsByBlockNumber(self: *Self, block_number: u64, allocator: Allocator) !Envelope([]types.Inherent) {
        const params = try self.allocator.alloc(u64, 1);
        defer self.allocator.free(params);
        params[0] = block_number;

        const ReqType = Request([]u64);
        var req = ReqType{ .method = "getInherentsByBlockNumber", .params = params };

        const ResponseType = Response([]types.Inherent);
        const parsed = try self.send(&req, ResponseType);
        defer parsed.deinit();

        var arena = ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        const inherents = try arena_allocator.alloc(types.Inherent, parsed.value.result.?.data.len);
        for (parsed.value.result.?.data, 0..) |inherent, index| {
            const cloned = try inherent.cloneArenaAlloc(arena_allocator);
            inherents[index] = cloned;
        }

        const EnvelopeType = Envelope([]types.Inherent);
        return EnvelopeType{ .block_number = block_number, .result = inherents, .arena = arena };
    }

    /// send a raw JSON-RPC request, returns the decoded JSON-RPC response
    pub fn send(self: *Self, req: anytype, comptime ResponseType: type) !json.Parsed(ResponseType) {
        const headers = std.http.Client.Request.Headers{
            .content_type = std.http.Client.Request.Headers.Value{
                .override = "application/json",
            },
        };

        const server_header_buffer: []u8 = try self.allocator.alloc(u8, 2048);
        defer self.allocator.free(server_header_buffer);

        var http_req = try self.client.open(.POST, self.uri, std.http.Client.RequestOptions{
            .server_header_buffer = server_header_buffer,
            .headers = headers,
        });
        defer http_req.deinit();

        const body = try req.marshalJSON(self.allocator);
        defer self.allocator.free(body);
        http_req.transfer_encoding = .{ .content_length = body.len };

        try http_req.send();
        _ = try http_req.writeAll(body);
        try http_req.finish();
        try http_req.wait();

        if (http_req.response.status != http.Status.ok) {
            return Error.UnexpectedHttpStatus;
        }

        const response_size = http_req.response.content_length orelse 1024;
        const json_str = try self.allocator.alloc(u8, @as(usize, response_size));
        defer self.allocator.free(json_str);
        _ = try http_req.reader().readAll(json_str);

        const parsed = try json.parseFromSlice(ResponseType, self.allocator, json_str, .{ .ignore_unknown_fields = true });
        if (parsed.value.@"error") |err| {
            return parseJsonRpcError(err);
        }

        return parsed;
    }

    fn parseJsonRpcError(err: ResponseError) Error {
        if (err.code == -32700) {
            return Error.ParseError;
        }

        if (err.code == -32600) {
            return Error.InvalidRequest;
        }

        if (err.code == -32601) {
            return Error.MethodNotFound;
        }

        if (err.code == -32602) {
            return Error.InvalidParams;
        }

        if (err.code == -32603) {
            return Error.InternalError;
        }

        if (err.code >= -32000 and err.code <= -32099) {
            return Error.ServerError;
        }

        return Error.UnknownError;
    }
};

test "jsonrpc" {
    try testing.expect(true);
}

const std = @import("std");
const http = std.http;
const json = std.json;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Uri = std.Uri;

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

        result: struct { data: T, metadata: ?struct {
            blockNumber: u64,
            blockHash: []const u8,
        } = null },
        @"error": ?ResponseError = null,
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
        const ReqType = Request([]bool);
        var req = ReqType{ .method = "getBlockNumber" };

        const ResponseType = Response(u64);

        const parsed = try self.send(&req, ResponseType);
        defer parsed.deinit();

        return parsed.value.result.data;
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

        var dest = std.ArrayList(u8).init(self.allocator);
        defer dest.deinit();

        const response_size = http_req.response.content_length orelse 1024;
        try http_req.reader().readAllArrayList(&dest, @as(usize, response_size));

        const parsed = try json.parseFromSlice(ResponseType, self.allocator, dest.allocatedSlice(), .{ .ignore_unknown_fields = true });
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

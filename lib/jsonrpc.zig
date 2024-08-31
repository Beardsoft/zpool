const std = @import("std");
const http = std.http;
const json = std.json;
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Uri = std.Uri;

const ResponseError = struct {
    code: i32,
    message: []u8,
    // we omit data field for now
    // data: []u8,
};

pub const Error = error{
    ParseError,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    ServerError,
    UnknownError,
};

pub const Client = struct {
    // TODO: in case of auth we have to handle bearer token based of username and password
    allocator: Allocator,
    client: *http.Client,
    uri: Uri,

    pub fn send(c: *Client, body: []u8, dest: *std.ArrayList(u8)) !void {
        const headers = std.http.Client.Request.Headers{
            .content_type = std.http.Client.Request.Headers.Value{
                .override = "application/json",
            },
        };

        const server_header_buffer: []u8 = try c.allocator.alloc(u8, 8 * 1024 * 4);

        var http_req = try c.client.open(.POST, c.uri, std.http.Client.RequestOptions{
            .server_header_buffer = server_header_buffer,
            .headers = headers,
        });
        defer http_req.deinit();
        defer c.allocator.free(server_header_buffer);

        http_req.transfer_encoding = .{ .content_length = body.len };

        try http_req.send();
        _ = try http_req.writeAll(body);
        try http_req.finish();
        try http_req.wait();
        try http_req.reader().readAllArrayList(dest, 1024);
    }

    const GetBlockNumberResponse = struct {
        result: struct { data: u64 },
        @"error": ?ResponseError = null,
    };

    pub fn getBlockNumber(c: *Client) !u64 {
        const payload = "{\"jsonrpc\":\"2.0\",\"method\":\"getBlockNumber\",\"id\":1,\"params\":[]}";

        const body = try c.allocator.alloc(u8, 62);
        defer c.allocator.free(body);
        @memcpy(body, payload);

        var buffer = std.ArrayList(u8).init(c.allocator);
        defer buffer.deinit();

        try c.send(body, &buffer);
        const response = try buffer.toOwnedSlice();

        const parsed = try json.parseFromSlice(GetBlockNumberResponse, c.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        if (parsed.value.@"error") |err| {
            return parseJsonRpcError(err);
        }

        return parsed.value.result.data;
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

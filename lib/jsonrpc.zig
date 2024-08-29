const std = @import("std");
const Allocator = std.mem.Allocator;
const HttpClient = std.http.Client;
const Uri = std.Uri;
const testing = std.testing;

const Client = struct {
    allocator: Allocator,
    client: HttpClient,
    uri: Uri,

    pub fn send(c: *Client, body: []u8) !void {
        const headers = std.http.Client.Request.Headers{
            .content_type = std.http.Client.Request.Headers.Value{
                .override = "application/json",
            },
        };

        const server_header_buffer: []u8 = try c.allocator.alloc(u8, 8 * 1024 * 4);

        var httpReq = try c.HttpClient.open(.POST, c.uri, std.http.Client.RequestOptions{
            .server_header_buffer = server_header_buffer,
            .headers = headers,
        });
        defer httpReq.deinit();
        defer c.allocator.free(server_header_buffer);

        try httpReq.send(.{});
        try httpReq.write(body);
        try httpReq.wait();

        const json_str = try httpReq.reader().readAllAlloc(c.allocator, std.math.maxInt(usize));
        defer c.allocator.free(json_str);
    }
};

test "jsonrpc" {
    try testing.expect(true);
}

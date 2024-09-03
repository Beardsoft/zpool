const std = @import("std");
const sqlite = @import("sqlite");

const Self = @This();

client: *sqlite.Db,

pub fn init(file_name: [:0]const u8) !*Self {
    var client = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = file_name },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });

    var self = Self{ .client = &client };
    return &self;
}

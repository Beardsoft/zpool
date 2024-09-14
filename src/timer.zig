const std = @import("std");
const time = std.time;

const Self = @This();

time_ms: i64,

pub fn new() Self {
    return .{ .time_ms = time.milliTimestamp() };
}

pub fn hasPassedDuration(self: Self, duration: i64) bool {
    const current_time = time.milliTimestamp();
    return (current_time - self.time_ms) > duration;
}

pub fn reset(self: *Self) void {
    self.time_ms = time.milliTimestamp();
}

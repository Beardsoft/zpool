const std = @import("std");
const Allocator = std.mem.Allocator;
const Config = @import("config.zig");

pub const InstructionType = enum {
    Collection,
};

pub const Instruction = struct { instruction_type: InstructionType, number: u64 };

const QueueType = std.DoublyLinkedList(Instruction);

pub const Queue = struct {
    queue: QueueType = QueueType{},
    allocator: Allocator,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn add(self: *Self, instruction: Instruction) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var node = try self.allocator.create(QueueType.Node);
        node.data = instruction;
        self.queue.append(node);
    }

    pub fn get(self: *Self) !?QueueType.Node {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.len == 0) return null;

        const node = self.queue.pop();

        if (node) |node_ptr| {
            defer self.allocator.destroy(node_ptr);
            const instruction = node_ptr.*.data;
            return instruction;
        }

        return null;
    }
};

pub const Timer = struct {
    const Self = @This();

    time_ms: i64,

    pub fn new() Timer {
        return .{ .time_ms = std.time.milliTimestamp() };
    }

    pub fn hasPassedDuration(self: Self, duration: i64) bool {
        const current_time = std.time.milliTimestamp();
        return (current_time - self.time_ms) > duration;
    }

    pub fn reset(self: *Self) void {
        self.time_ms = std.time.milliTimestamp();
    }
};

pub const WorkerArgs = struct {};

pub fn run(_: WorkerArgs) !void {
    std.log.info("running on a thread", .{});

    const interval_queue_consume = 1 * std.time.ms_per_min;

    var timer = Timer.new();
    while (true) {
        if (timer.hasPassedDuration(interval_queue_consume)) {
            std.log.info("a minute has passed", .{});
            timer.reset();
        }

        std.time.sleep(15 * std.time.ns_per_s);
    }
}

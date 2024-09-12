const std = @import("std");
const Allocator = std.mem.Allocator;
const Config = @import("config.zig");
const http = std.http;
const sqlite = @import("sqlite.zig");

const zpool = @import("zpool");
const jsonrpc = zpool.jsonrpc;

pub const InstructionType = enum {
    Collection,
};

pub const Instruction = struct { instruction_type: InstructionType, number: u64 };

const QueueType = std.DoublyLinkedList(Instruction);

pub const Queue = struct {
    queue: QueueType = QueueType{},
    allocator: Allocator,
    mutex: std.Thread.RwLock = std.Thread.RwLock{},
    closed: bool = false,

    const Self = @This();

    pub fn add(self: *Self, instruction: Instruction) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var node = try self.allocator.create(QueueType.Node);
        node.data = instruction;
        self.queue.append(node);
    }

    pub fn get(self: *Self) !?Instruction {
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

    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;

        while (self.queue.len > 0) {
            const node = self.queue.pop();
            if (node) |node_ptr| {
                self.allocator.destroy(node_ptr);
            }
        }
    }

    pub fn isClosed(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.closed;
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

pub const Args = struct {
    queue: *Queue,
    cfg: *Config,
};

pub const Process = struct {
    const Self = @This();

    queue: *Queue,
    cfg: *Config,

    pub fn run(self: *Self) !void {
        std.log.info("started worker thread", .{});

        const interval_queue_consume = 1 * std.time.ms_per_min;

        var queue_timer = Timer.new();
        while (!self.queue.isClosed()) {
            if (queue_timer.hasPassedDuration(interval_queue_consume)) {
                queue_timer.reset();

                if (try self.queue.get()) |instruction| {
                    try self.handleInstruction(instruction);
                }
            }

            std.time.sleep(15 * std.time.ns_per_s);
        }

        std.log.info("worker stopped", .{});
    }

    fn handleInstruction(_: *Self, instruction: Instruction) !void {
        std.log.info("got instruction: {}, {}", .{ instruction.instruction_type, instruction.number });
    }
};

pub fn run(args: Args) !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    // var client = http.Client{ .allocator = allocator };
    // defer client.deinit();
    // const uri = try std.Uri.parse(args.cfg.rpc_url);
    // var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    // var sqlite_conn = try sqlite.open(args.cfg.sqlite_db_path);
    var worker_process = Process{ .cfg = args.cfg, .queue = args.queue };
    try worker_process.run();
}

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const InstructionType = enum {
    Collection,
};

pub const Instruction = struct { instruction_type: InstructionType, number: u32 };

const QueueType = std.DoublyLinkedList(Instruction);

const Self = @This();

var interrupted = false;

queue: QueueType = QueueType{},
allocator: Allocator,
mutex: std.Thread.RwLock = std.Thread.RwLock{},
closed: bool = false,

pub fn add(self: *Self, instruction: Instruction) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var node = try self.allocator.create(QueueType.Node);
    node.data = instruction;
    self.queue.prepend(node);
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

pub fn hasInstructions(self: *Self) bool {
    self.mutex.lockShared();
    defer self.mutex.unlockShared();
    return (self.queue.len > 0);
}

pub fn close(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.closed) return;

    self.closed = true;

    while (self.queue.len > 0) {
        const node = self.queue.pop();
        if (node) |node_ptr| {
            self.allocator.destroy(node_ptr);
        }
    }
}

pub fn isClosed(self: *Self) bool {
    if (interrupted) self.close();

    self.mutex.lockShared();
    defer self.mutex.unlockShared();

    return self.closed;
}

// TODO:
// this is rather hacky and should probably employ
// atomics for Thread safety
pub fn signalHandler(_: c_int) callconv(.C) void {
    interrupted = true;
}

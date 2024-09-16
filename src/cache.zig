const std = @import("std");
const atomic = std.atomic;
const AtomicOrder = std.builtin.AtomicOrder;

var block_number = atomic.Value(u32).init(0);

pub fn block_number_store(number: u32) void {
    block_number.store(number, AtomicOrder.monotonic);
}

pub fn block_number_get() u32 {
    return block_number.load(AtomicOrder.monotonic);
}

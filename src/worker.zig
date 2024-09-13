const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;

const Config = @import("config.zig");
const querier = @import("querier.zig");
const sqlite = @import("sqlite.zig");

const zpool = @import("zpool");
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;

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
    client: *jsonrpc.Client,
    sqlite_conn: *sqlite.Conn,
    allocator: Allocator,

    pub fn run(self: *Self) !void {
        std.log.info("started worker thread", .{});

        const interval_queue_consume = 1 * std.time.ms_per_min;

        var queue_timer = Timer.new();
        while (!self.queue.isClosed()) {
            if (queue_timer.hasPassedDuration(interval_queue_consume)) {
                queue_timer.reset();

                // TODO:
                // this should empty the queue
                if (try self.queue.get()) |instruction| {
                    try self.handleInstruction(instruction);
                }
            }

            std.time.sleep(15 * std.time.ns_per_s);
        }

        std.log.info("worker stopped", .{});
    }

    fn handleInstruction(self: *Self, instruction: Instruction) !void {
        switch (instruction.instruction_type) {
            InstructionType.Collection => try self.handleNewCollection(instruction.number),
        }
    }

    fn handleNewCollection(self: *Self, collection_number: u64) !void {
        const first_batch = policy.getFirstBatchFromCollection(collection_number);
        const epoch_number = policy.getEpochFromBatchNumber(first_batch);

        const epoch_status = querier.epochs.getEpochStatusByNumber(self.sqlite_conn, epoch_number) catch |err| {
            if (err == querier.epochs.QueryError.NotFound) {
                std.log.warn("collection passed for epoch {d}, but epoch is not found", .{epoch_number});
                return;
            }

            std.log.err("error getting epoch status for epoch {d}: {}", .{ epoch_number, err });
            return err;
        };

        if (epoch_status.isInvalid()) {
            std.log.warn("collection {d} passed for invalid epoch {d} with status {}. Ignoring collection", .{ collection_number, epoch_number, epoch_status });
        }

        // TODO:
        // probably want to check the database if we have handled the collection already

        std.log.info("Collection {d} passed for epoch {d}. Fetching rewards.", .{ collection_number, epoch_number });

        var reward: u64 = 0;
        var batch_index: u64 = 0;

        // TODO: double check this includes all batches
        batch_loop: while (batch_index < policy.collection_batches) : (batch_index += 1) {
            const batch_number = first_batch + batch_index;
            var batch_inherents = self.client.getInherentsByBlockNumber(policy.getBlockNumberForBatch(batch_number), self.allocator) catch |err| {
                std.log.err("Failed to get inherents for collection {d}, batch {d}: {}", .{ collection_number, batch_number, err });
                return err;
            };
            defer batch_inherents.deinit();

            inherent_loop: for (0..batch_inherents.result.len) |index| {
                var inherent = batch_inherents.result[index];
                if (!inherent.isReward()) {
                    continue :inherent_loop;
                }

                if (inherent.validatorAddress == null) {
                    continue :inherent_loop;
                }

                const validator_address = inherent.validatorAddress.?;
                if (!std.mem.eql(u8, validator_address, self.cfg.validator_address)) {
                    continue :inherent_loop;
                }

                if (inherent.value == null) {
                    continue :inherent_loop;
                }

                reward += inherent.value.?;
                continue :batch_loop;
            }
        }

        std.log.info("Reward for collection {d} completed: {d}", .{ collection_number, reward });

        // TODO:
        // the reward and pool fee does not consider the stake of the validator itself
        // we could theoretically consider this pool fee as well, but we can also leave it as is
        const pool_fee = reward / 100 * self.cfg.pool_fee_percentage;
        reward -= pool_fee;

        try querier.rewards.insertNewReward(self.sqlite_conn, epoch_number, collection_number, reward, pool_fee);

        const stakers = try querier.stakers.getStakersByEpoch(self.sqlite_conn, self.allocator, epoch_number);
        defer stakers.deinit();

        for (stakers.data) |staker| {
            const staker_reward: u64 = @intFromFloat(@as(f64, @floatFromInt(reward)) / 100.00 * staker.stake_percentage);
            std.log.info("Staker {s} is owed {d} for collection {d}", .{ staker.address, staker_reward, collection_number });

            // TODO:
            // store payslip
        }
    }
};

pub fn run(args: Args) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();
    const uri = try std.Uri.parse(args.cfg.rpc_url);
    var jsonrpc_client = jsonrpc.Client{ .allocator = allocator, .client = &client, .uri = uri };

    var sqlite_conn = try sqlite.open(args.cfg.sqlite_db_path);
    var worker_process = Process{ .cfg = args.cfg, .queue = args.queue, .sqlite_conn = &sqlite_conn, .client = &jsonrpc_client, .allocator = allocator };
    try worker_process.run();
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;
const http = std.http;

const Config = @import("config.zig");
const querier = @import("querier.zig");
const Queue = @import("queue.zig");
const sqlite = @import("sqlite.zig");
const timer = @import("timer.zig");

const zbackoff = @import("zbackoff");

const zpool = @import("zpool");
const Address = zpool.address;
const jsonrpc = zpool.jsonrpc;
const policy = zpool.policy;
const types = zpool.types;

pub const Args = struct {
    queue: *Queue,
    cfg: *Config,
};

pub const WorkerError = error{
    InherentFailed,
};

/// run starts the worker process. The worker process is meant to be run
/// on a separate Thread.
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

pub const Process = struct {
    const Self = @This();

    reward_address: Address = Address{},
    reward_address_key_pair: Ed25519.KeyPair = undefined,
    queue: *Queue,
    cfg: *Config,
    client: *jsonrpc.Client,
    sqlite_conn: *sqlite.Conn,
    allocator: Allocator,

    pub fn run(self: *Self) !void {
        std.log.info("started worker thread", .{});

        try self.reward_address.parseAddressFromFriendly(self.cfg.reward_address);

        var private_key_raw = try self.allocator.alloc(u8, self.cfg.reward_address_secret_key.len / 2);
        defer self.allocator.free(private_key_raw);
        private_key_raw = try std.fmt.hexToBytes(private_key_raw, self.cfg.reward_address_secret_key[0..]);

        var private_key_seed = [_]u8{0} ** 32;
        @memcpy(&private_key_seed, private_key_raw);

        self.reward_address_key_pair = try Ed25519.KeyPair.create(private_key_seed);

        var scheduled_task_tracker = timer.new();

        while (!self.queue.isClosed()) {
            while (self.queue.hasInstructions()) {
                if (try self.queue.get()) |instruction| {
                    try self.handleInstruction(instruction);
                }
            }

            if (scheduled_task_tracker.hasPassedDuration(std.time.ms_per_s * 300)) {
                scheduled_task_tracker.reset();

                try self.executePendingPayments();
            }

            std.time.sleep(2 * std.time.ns_per_s);
        }

        std.log.info("worker stopped", .{});
    }

    fn handleInstruction(self: *Self, instruction: Queue.Instruction) !void {
        switch (instruction.instruction_type) {
            Queue.InstructionType.Collection => try self.handleNewCollection(instruction.number),
        }
    }

    fn handleNewCollection(self: *Self, collection_number: u32) !void {
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
        var batch_index: u32 = 0;

        // TODO: double check this includes all batches
        batch_loop: while (batch_index < policy.collection_batches) : (batch_index += 1) {
            const batch_number = first_batch + batch_index;

            var backoff = zbackoff.Backoff{};
            var batch_inherents: jsonrpc.Envelope([]types.Inherent) = undefined;
            var success = false;

            // Because this Thread only occasionly does HTTP requests the underlying connection could be closed
            // we therefore employ retries.
            // related: https://github.com/ziglang/zig/issues/19165
            retry_loop: for (0..3) |_| {
                const result = self.client.getInherentsByBlockNumber(policy.getBlockNumberForBatch(batch_number), self.allocator) catch |err| {
                    std.log.debug("Failed to get inherents for collection {d}, batch {d}: {}. Attempting retry", .{ collection_number, batch_number, err });
                    std.time.sleep(backoff.pause());
                    continue :retry_loop;
                };

                batch_inherents = result;
                success = true;
                break;
            }

            if (!success) {
                std.log.err("Failed to get inherents for collection {d}, batch {d}", .{ collection_number, batch_number });
                return WorkerError.InherentFailed;
            }

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
        // depending on the slots of the validator the rewards could be 0
        // this should be handled here

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

            try querier.payslips.insertNewPayslip(self.sqlite_conn, collection_number, staker.address, staker_reward, querier.statuses.Status.Pending);
        }
    }

    fn executePendingPayments(self: *Self) !void {
        const pending_payments = try querier.payslips.getPendingHigherThanMinPayout(self.sqlite_conn, self.allocator);
        defer pending_payments.deinit();

        for (pending_payments.data) |pending_payment| {
            std.log.info("Staker {s} will receive {d}", .{ pending_payment.address, pending_payment.amount });
        }
    }
};

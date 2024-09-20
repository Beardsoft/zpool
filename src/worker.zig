const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;
const http = std.http;

const config = @import("config.zig");
const cache = @import("cache.zig");
const querier = @import("querier.zig");
const Queue = @import("queue.zig");
const sqlite = @import("sqlite.zig");
const timer = @import("timer.zig");
const zbackoff = @import("zbackoff");

const nimiq = @import("nimiq.zig");
const Address = nimiq.address;
const jsonrpc = nimiq.jsonrpc;
const policy = nimiq.policy;
const Builder = nimiq.transaction_builder.Builder;
const types = nimiq.types;

pub const Args = struct {
    queue: *Queue,
    cfg: *config.Config,
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

    queue: *Queue,
    cfg: *config.Config,
    client: *jsonrpc.Client,
    sqlite_conn: *sqlite.Conn,
    allocator: Allocator,

    pub fn run(self: *Self) !void {
        std.log.info("started worker thread", .{});

        var scheduled_task_tracker = timer.new();

        while (!self.queue.isClosed()) {
            while (self.queue.hasInstructions()) {
                if (try self.queue.get()) |instruction| {
                    try self.handleInstruction(instruction);
                }
            }

            if (scheduled_task_tracker.hasPassedDuration(std.time.ms_per_s * 300)) {
                scheduled_task_tracker.reset();

                try self.checkTransactionConfirmations();
                try self.checkFinalizedEpochs();
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

        const epoch_details = querier.epochs.getEpochDetailsByNumber(self.sqlite_conn, epoch_number) catch |err| {
            if (err == querier.epochs.QueryError.NotFound) {
                std.log.warn("collection passed for epoch {d}, but epoch is not found", .{epoch_number});
                return;
            }

            std.log.err("error getting epoch status for epoch {d}: {}", .{ epoch_number, err });
            return err;
        };

        if (epoch_details.status.isInvalid()) {
            std.log.warn("collection {d} passed for invalid epoch {d} with status {}. Ignoring collection", .{ collection_number, epoch_number, epoch_details.status });
        }

        // TODO:
        // probably want to check the database if we have handled the collection already

        std.log.info("Collection {d} passed for epoch {d}. Fetching rewards.", .{ collection_number, epoch_number });

        var reward: u64 = 0;
        var batch_index: u32 = 0;

        batch_loop: while (batch_index < policy.collection_batches) : (batch_index += 1) {
            const batch_number = first_batch + batch_index;
            var batch_inherents = self.client.getInherentsByBlockNumber(policy.getBlockNumberForBatch(batch_number), self.allocator) catch |err| {
                std.log.err("Failed to get inherents for collection {d}, batch {d}: {}. Attempting retry", .{ collection_number, batch_number, err });
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

        if (reward == 0) {
            try querier.rewards.insertNewReward(self.sqlite_conn, epoch_number, collection_number, reward, 0, 0);
            return;
        }

        // TODO:
        // the reward and pool fee does not consider the stake of the validator itself
        // we could theoretically consider this pool fee as well, but we can also leave it as is
        const pool_fee = reward / 100 * self.cfg.pool_fee_percentage;
        reward -= pool_fee;

        try querier.rewards.insertNewReward(self.sqlite_conn, epoch_number, collection_number, reward, pool_fee, epoch_details.num_stakers);

        var stakers = try querier.stakers.getStakersByEpoch(self.sqlite_conn, self.allocator, epoch_number);
        defer stakers.deinit();

        for (stakers.value) |staker| {
            const staker_reward: u64 = @intFromFloat(@as(f64, @floatFromInt(reward)) / 100.00 * staker.stake_percentage);
            std.log.info("Staker {s} is owed {d} for collection {d}", .{ staker.address, staker_reward, collection_number });

            try querier.payslips.insertNewPayslip(self.sqlite_conn, collection_number, staker.address, staker_reward, querier.statuses.Status.Pending);
        }
    }

    // this will execute pending payments. It does bundle open payments together and will only
    // do a payout once a minimum payout amount is reached. All transactions are tracked
    // as pending until they are confirmed.
    fn executePendingPayments(self: *Self) !void {
        try querier.payslips.setElligableToOutForPayment(self.sqlite_conn);
        var pending_payments = try querier.payslips.getOutForPayment(self.sqlite_conn, self.allocator);
        defer pending_payments.deinit();

        for (pending_payments.value) |pending_payment| {
            var recipient_address = Address{};
            try recipient_address.parseAddressFromFriendly(pending_payment.address);

            var tx_builder = try Builder.newAddStake(self.allocator, self.cfg.reward_address, recipient_address, pending_payment.amount, cache.block_number_get());
            defer tx_builder.deinit();
            try tx_builder.setFeeByByteSize();

            const raw_tx_hex = try tx_builder.signAndCompile(self.allocator, self.cfg.reward_address_key_pair);
            defer self.allocator.free(raw_tx_hex);

            const tx_hash = try self.client.sendRawTransaction(raw_tx_hex, self.allocator);
            defer self.allocator.free(tx_hash);

            try querier.transactions.insertNewTransaction(self.sqlite_conn, tx_hash, pending_payment.address, pending_payment.amount, querier.statuses.Status.AwaitingConfirmation);
            try querier.payslips.setTransaction(self.sqlite_conn, tx_hash, pending_payment.address);

            std.log.info("Staker {s} will receive {d}. Tx hash: {s}", .{ pending_payment.address, pending_payment.amount, tx_hash });
        }
    }

    // this will check all pending transactions, and mark them completed if the
    // transaction is mined, a new macro block has passed and the execution result is true
    // one a transaction is considered completed, all corresponding payslips for that transaction
    // will be marked completed as well.
    fn checkTransactionConfirmations(self: *Self) !void {
        var pending_txs = try querier.transactions.getTransactionHashesAwaitingConfirmation(self.sqlite_conn, self.allocator);
        defer pending_txs.deinit();

        for (pending_txs.value) |pending_tx| {
            const pending_tx_hash = pending_tx.hash;
            const transaction = self.client.getTransactionByHash(pending_tx_hash) catch |err| {
                // TODO
                // It could be the transaction was never mined. This should be checked and perhaps
                // retried in the future
                std.log.err("could not retrieve tx with hash {s}: {}", .{ pending_tx_hash, err });
                continue;
            };

            if (!transaction.isConfirmed(cache.block_number_get())) {
                std.log.warn("tx with hash {s} is not yet confirmed", .{pending_tx_hash});
                continue;
            }

            if (!transaction.executionResult) {
                std.log.warn("tx with hash {s} failed", .{pending_tx_hash});
                // TODO
                // this failed so has to be retried. Update state so this transaction will be retried
                // during a next iteration.
                continue;
            }

            std.log.info("tx with hash {s} is confirmed", .{pending_tx_hash});
            try querier.transactions.setStatus(self.sqlite_conn, pending_tx_hash, querier.statuses.Status.Completed);
            try querier.payslips.finalize(self.sqlite_conn, pending_tx_hash);
        }
    }

    fn checkFinalizedEpochs(self: *Self) !void {
        const payment_details = try querier.epochs.getPaymentsCompletedByInProgress(self.sqlite_conn, self.allocator);
        defer self.allocator.free(payment_details);

        for (payment_details) |summary| {
            if ((summary.num_stakers * policy.collections_per_epoch) != summary.number_of_payments) continue;

            std.log.info("All payments for epoch {d} completed", .{summary.epoch_number});
            try querier.epochs.setStatus(self.sqlite_conn, summary.epoch_number, querier.statuses.Status.Completed);
        }
    }
};

const std = @import("std");
const sqlite = @import("../sqlite.zig");

const migration_version = 1;

pub const MigrationError = error{
    UnknownVersion,
};

pub fn execute(conn: *sqlite.Conn) !void {
    const migrations_exist = try doesMigrationTableExist(conn);

    var current_migration: u64 = 0;
    if (migrations_exist) {
        current_migration = try getMigrationVersion(conn);
    } else {
        std.log.info("No prior migrations found, assuming version 0", .{});
    }

    while (current_migration < migration_version) : (current_migration += 1) {
        try executeMigrationByVersion(conn, current_migration);
    }

    std.log.info("All migrations complete", .{});
}

fn doesMigrationTableExist(conn: *sqlite.Conn) !bool {
    const result = conn.row("SELECT name FROM sqlite_master WHERE type='table' AND name='migrations';", .{}) catch |err| {
        std.log.err("Got error checking for migration table: {}. Assuming no migrations are present", .{err});
        return false;
    };

    if (result) |row| {
        defer row.deinit();
        return true;
    }

    return false;
}

fn getMigrationVersion(conn: *sqlite.Conn) !u64 {
    const result = try conn.row("SELECT version FROM migrations;", .{});
    if (result) |row| {
        defer row.deinit();
        return @intCast(row.int(0));
    }

    return 0;
}

const migration_version_0 =
    \\CREATE TABLE migrations (
    \\    version INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS cursors(
    \\    id INTEGER NOT NULL PRIMARY KEY,
    \\    block_number INTEGER NOT NULL
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS statuses(
    \\    id INTEGER NOT NULL PRIMARY KEY,
    \\    status TEXT NOT NULL
    \\);
    \\
    \\INSERT INTO statuses(id, status) VALUES 
    \\    (0, "NOT_ELECTED"),
    \\    (1, "NO_STAKERS"),
    \\    (2, "RETIRED"),
    \\    (3, "INACTIVE"),
    \\    (4, "ERROR"),
    \\    (5, "IN_PROGRESS"),
    \\    (6, "COMPLETED"),
    \\    (7, "PENDING"),
    \\    (8, "OUT_FOR_PAYMENT"),
    \\    (9, "AWAITING_CONFIRMATION");
    \\
    \\CREATE TABLE IF NOT EXISTS epochs(
    \\    number INTEGER NOT NULL PRIMARY KEY,
    \\    num_stakers INTEGER NOT NULL,
    \\    balance INTEGER NOT NULL,
    \\    status_id INTEGER NOT NULL,
    \\
    \\    FOREIGN KEY(status_id) REFERENCES statuses(id)
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS stakers(
    \\    address TEXT NOT NULL,
    \\    epoch_number INTEGER NOT NULL,
    \\    stake_balance INTEGER NOT NULL,
    \\    stake_percentage REAL NOT NULL,
    \\
    \\    PRIMARY KEY (address, epoch_number),
    \\    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS rewards(
    \\    epoch_number INTEGER NOT NULL,
    \\    collection_number INTEGER NOT NULL,
    \\    reward INTEGER NOT NULL,
    \\    pool_fee INTEGER NOT NULL,
    \\
    \\    PRIMARY KEY(epoch_number, collection_number),
    \\    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS transactions(
    \\    hash TEXT NOT NULL PRIMARY KEY,
    \\    address TEXT NOT NULL,
    \\    amount INTEGER NOT NULL,
    \\    status_id INTEGER NOT NULL,
    \\
    \\    FOREIGN KEY(status_id) REFERENCES statuses(id)
    \\);
    \\
    \\CREATE TABLE IF NOT EXISTS payslips(
    \\    collection_number INTEGER NOT NULL,
    \\    address TEXT NOT NULL,
    \\    amount INTEGER NOT NULL,
    \\    status_id INTEGER NOT NULL,
    \\    tx_hash TEXT,
    \\
    \\    PRIMARY KEY(collection_number, address),
    \\    FOREIGN KEY(collection_number) REFERENCES rewards(collection_number),
    \\    FOREIGN KEY(status_id) REFERENCES statuses(id),
    \\    FOREIGN KEY(tx_hash) REFERENCES transactions(hash)
    \\);
    \\
    \\INSERT INTO migrations(version) VALUES(1);
;

fn executeMigrationByVersion(conn: *sqlite.Conn, version: u64) !void {
    switch (version) {
        0 => {
            try conn.execNoArgs(migration_version_0);
        },
        else => {
            return MigrationError.UnknownVersion;
        },
    }

    std.log.info("Executed migration for version {d}", .{migration_version});
}

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
    \\CREATE TABLE IF NOT EXISTS cursors(
    \\    id INTEGER NOT NULL PRIMARY KEY,
    \\    block_number UNSIGNED BIGINT NOT NULL
    \\);
    \\CREATE TABLE IF NOT EXISTS epochs(
    \\    number UNSIGNED BIGINT NOT NULL PRIMARY KEY,
    \\    num_stakers INTEGER NOT NULL,
    \\    balance UNSIGNED BIGINT NOT NULL
    \\);
    \\CREATE TABLE IF NOT EXISTS stakers(
    \\    address VARCHAR(44) NOT NULL,
    \\    epoch_number UNSIGNED BIGINT NOT NULL,
    \\    stake_balance UNSIGNED BIGINT NOT NULL,
    \\    stake_percentage REAL NOT NULL,
    \\
    \\    PRIMARY KEY (address, epoch_number),
    \\    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
    \\);
    \\CREATE TABLE IF NOT EXISTS rewards(
    \\    epoch_number UNSIGNED BIGINT NOT NULL,
    \\    collection_number UNSIGNED BIGINT NOT NULL,
    \\    reward UNSIGNED BIGINT NOT NULL,
    \\
    \\    PRIMARY KEY(epoch_number, collection_number),
    \\    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
    \\);
    \\CREATE TABLE IF NOT EXISTS transactions(
    \\    hash VARCHAR(255) NOT NULL PRIMARY KEY,
    \\    address VARCHAR(44) NOT NULL,
    \\    amount UNSIGNED BIGINT NOT NULL
    \\);
    \\CREATE TABLE IF NOT EXISTS payslips(
    \\    collection_number UNSIGNED BIGINT NOT NULL,
    \\    address VARCHAR(44) NOT NULL,
    \\    amount UNSIGNED BIGINT NOT NULL,
    \\    fee UNSIGNED BIGINT NOT NULL,
    \\    tx_hash VARCHAR(255),
    \\
    \\    PRIMARY KEY(collection_number, address),
    \\    FOREIGN KEY(collection_number) REFERENCES rewards(collection_number),
    \\    FOREIGN KEY(tx_hash) REFERENCES transactions(hash)
    \\);
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

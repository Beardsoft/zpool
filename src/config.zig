const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Ed25519 = std.crypto.sign.Ed25519;
const nimiq = @import("nimiq.zig");
const Address = nimiq.address;
const toml = @import("zig-toml");
const ArenaWrapped = @import("utils.zig").ArenaWrapped;

pub const Config = struct {
    sqlite_db_path: [:0]const u8 = "./zpool.db",

    rpc_url: []const u8 = "http://seed1.nimiq.local:8648",
    rpc_username: ?[]const u8 = null,
    rpc_password: ?[]const u8 = null,

    validator_address: []const u8,
    reward_address: Address,
    reward_address_key_pair: Ed25519.KeyPair = undefined,
    pool_fee_percentage: u64 = 5,
    min_payout_luna: u64 = 1000000,
};

pub const ConfigToml = struct {
    sqlite_db_path: []const u8 = "./zpool.db",

    rpc_url: []const u8 = "http://seed1.nimiq.local:8648",
    rpc_username: ?[]const u8 = null,
    rpc_password: ?[]const u8 = null,

    validator: struct {
        address: []const u8,
        reward_address: []const u8,
        reward_secret_key: []const u8,
    },

    pool: PoolConfig = PoolConfig{},
};

const PoolConfig = struct {
    fee_percentage: u64 = 5,
    min_payout_luna: u64 = 1000000, // 10 NIM
};

pub const ConfigError = error{
    ConfigEnvNotDefined,
};

// TODO
// The config loading should employ validation of inputs
pub fn load(allocator: Allocator) !ArenaWrapped(Config) {
    const config_file_path = std.posix.getenv("ZPOOL_CONFIG_FILE") orelse return ConfigError.ConfigEnvNotDefined;

    var parser = toml.Parser(ConfigToml).init(allocator);
    defer parser.deinit();

    const result = try parser.parseFile(config_file_path);
    defer result.deinit();

    var arena = ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();

    var reward_address = Address{};
    try reward_address.parseAddressFromFriendly(result.value.validator.reward_address);

    var cfg = Config{
        .sqlite_db_path = try Allocator.dupeZ(arena_allocator, u8, result.value.sqlite_db_path),
        .rpc_url = try Allocator.dupe(arena_allocator, u8, result.value.rpc_url),
        .validator_address = try Allocator.dupe(arena_allocator, u8, result.value.validator.address),
        .reward_address = reward_address,
        .pool_fee_percentage = result.value.pool.fee_percentage,
        .min_payout_luna = result.value.pool.min_payout_luna,
    };

    var private_key_raw = try allocator.alloc(u8, result.value.validator.reward_secret_key.len / 2);
    defer allocator.free(private_key_raw);
    private_key_raw = try std.fmt.hexToBytes(private_key_raw, result.value.validator.reward_secret_key[0..]);

    var private_key_seed = [_]u8{0} ** 32;
    @memcpy(&private_key_seed, private_key_raw);

    cfg.reward_address_key_pair = try Ed25519.KeyPair.create(private_key_seed);

    if (result.value.rpc_username) |username| {
        cfg.rpc_username = try Allocator.dupe(arena_allocator, u8, username);
    }

    if (result.value.rpc_password) |password| {
        cfg.rpc_password = try Allocator.dupe(arena_allocator, u8, password);
    }

    return ArenaWrapped(Config){ .arena = arena, .value = cfg };
}

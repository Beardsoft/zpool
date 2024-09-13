const Self = @This();

sqlite_db_path: [:0]const u8 = "./zpool.db",

rpc_url: []const u8 = "http://seed1.nimiq.local:8648",
rpc_username: ?[]const u8 = null,
rpc_password: ?[]const u8 = null,

validator_address: []const u8 = "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
reward_address: []const u8 = "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
pool_fee_percentage: u64 = 5,

const Self = @This();

sqlite_db_path: [:0]const u8 = "./zpool.db",

rpc_url: []const u8 = "http://seed1.nimiq.local:8648",
rpc_username: ?[]const u8 = null,
rpc_password: ?[]const u8 = null,

validator_address: []const u8 = "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
reward_address: []const u8 = "NQ46 U66M JNLD 0DJ7 0E9P Q7XR V9KV H976 813A",
reward_address_secret_key: []const u8 = "6c9320ac201caf1f8eaa5b05f5d67a9e77826f3f6be266a0ecccc20416dc6587",
pool_fee_percentage: u64 = 5,

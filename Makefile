
testnet:
	zig build -Dpolicy=Testnet -Doptimize=ReleaseSafe

devnet:
	zig build -Dpolicy=Devnet -Doptimize=Debug

mainnet:
	zig build -Dpolicy=Mainnet -Doptimize=ReleaseSafe

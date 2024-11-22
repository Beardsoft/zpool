# How to run devnet

## Requirements
In order to run zpool in devnet mode, you need the following:
* a Linux or MacOs machine running zig 0.13.0. See https://ziglang.org for installation instructions.
* a machine that has `docker`, `docker compose` and `git` installed.

## Step 1: run albatross in devnet mode 
1. Enter the devlab folder 
```
cd devlab
```
2. Sync albatross 
```
./run.sh sync
```
3. Apply patches. Zpool uses an altered policy for devnet so that epochs only take 8 minutes. You have to apply the `/devlab/devnet-policy.path` on the `/devlab/albatross` folder. 
4. build albatross 
```
./run.sh build-albatross
```
5. Run albatross in docker 
```
./run.sh up-albatross
```
6. Add below to your hosts file
```
127.0.0.1       seed1.nimiq.local
```

## Step 2: build and run zpool
1. Build zpool. As mentioned in the requirements you need `zig` version 0.13.0 to compile zpool. Additionally you need to install the `sqlite3` dev libraries for your system. Run below in the root of the project folder:
```
zig build -Dpolicy=Devnet -Doptimize=Debug
```
2. Run zpool.
```
ZPOOL_CONFIG_FILE=./devnet.config.toml ./zig-out/bin/zpool
```
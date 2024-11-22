# zpool
zpool is an open source Proof of Stake pool for the Nimiq blockchain.

## Status
The pool is meant to be a reference implementation. The core functionality works and has run on devnet and testnet. Pool has not been tested thoroughly, so there might be problems or issues that are currently not handled yet. The pool might be optimized for mainnet in the future if there is interest.

## Goal
The goal of this project is to provide a simple PoS pool implementation as a starting point for pool operators. 
By making the pool open source, we hope to contribute to the Nimiq eco system as a whole providing other pool operators a blue print for their own implementations.

## Features
* keeps track of validator election
* keeps track of delegated stakers per epoch
* keeps track of validator rewards
* distributes validator rewards to relevant delegated stakers
* deducts a configurable pool fee 
* uses offline transaction creation and signing, this removes the necessatiy of importing and unlocking the account on a node
* validates transaction confirmations
* stores state in sqlite3
* is very lightweight, requiring minimal hardware to run

## Features it will not provide
* will not provide a frontend

## Documentation
Please see the [doc](/doc/) folder for documentation on the pool.
1. [How to run zpool](/doc/how-to-run.md)
2. [Building your own pool](/doc/DESIGN.md)

# zpool
zpool is an open source Proof of Stake pool for the Nimiq blockchain meant to serve as an example / refernce implementation for other pool operators.

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
* does not support genesis validators. Considering mainnet is already launched, this is no longer relevant.
* pool fee is not paid out to the operator automatically. The pool fee is deducted though, and the amount is stored in the database.

## Documentation
Please see the [doc](/doc/) folder for documentation on the pool.
1. [How to run zpool on devnet](/doc/how-to-run-devnet.md)
2. [Building your own pool](/doc/DESIGN.md)

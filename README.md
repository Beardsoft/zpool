# zpool
zpool is an open source Proof of Stake pool for the Nimiq blockchain.

## Status
The pool is currently in development and in an alpha phase. Most of the core functionality is working, but certain edge cases and errors are to be expected in this stage. Pool is currently being tested on testnet in preparation for mainnet running.

## Goal
The goal of this project is to provide a simple PoS pool implementation as a starting point for pool operators. 
zpool is small and simple to run, capable of handling a maximum of 500 stakers. Proper handling of more stakers is not gauranteed.
By making the pool open source, we hope to contribute to the Nimiq eco system as a whole providing other pool operators a blue print for their own implementations.

## Features
* is easy to run
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

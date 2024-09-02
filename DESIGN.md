# Generic pool algorithm

1. Watch for block progression. 
   * When an election block approaches, goto A
   * When a checkpoint block passes, goto B
2. Payout rewards, goto C

## A - Election block
When an election block approaches we want to retrieve the validator state for the new epoch. The validator state is kept in the staking contract, which does not have history. This means that the staking contract state can only be retrieved during an election block, or in the last micro block proceeding the election block. Hereafter we just refer to the election block, but either block is fine.

1. call `getValidatorByAddress` for your validator.
   * if the validator is not returned, you are not a validator.
   * if `inctivityFlag` is not `null`  check that the block number is not higher than the current block height.
      * if the inactivityFlag is higher than the current height your validator is inactive
   * if `retired` is true, your validator is retired
   * if `jailedFrom`  is not `null`  check that the block number is not higher than the current block height.
      * if the jailedFrom is higher than the current height your validator is jailed
2. the `balance`  field is the validator stake. This includes both the validator balance and all delegated funds. The `numStakers` field indicates the amount of delegated stakers. See below for example.
```
{
    "jsonrpc": "2.0",
    "result": {
        "data": {
            "address": "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
            "signingKey": "7a4d16d80d0afab4af8dc38e4ebd20cf46f5b8aa8cd5baa45a52717ae976119c",
            "votingKey": "333b4a431577598ae558e047502139a8e91f22c23dc195b2b741b17a4dcbc30e66b1bfe7ec08032616a1b393c1d785dbbb780cc110502c494f543caba088a3fdfa519c1f07f5f084005a00390b406f98fbedab6bc7538d8c75373e7f4cf60082c26d697f8029c07307ab9e0bb87435215e22cff141147b1ac6d3604ec8f21598985d107255707dee6dddc4590414ebefbe51932c74c4f8a3eb412123d5c9ea50901f8a2cdabc82fc957da7a5c14029edd228ea7e8ec2707cd63b2f105c01174a26ca75043d6c8ce43bfc57802def7ce493520dbc4f149d84d4ee66f712a56203f097c63211e1ce3d4c7b85c5f38170385769c738c05be983887774c3a8b8d04482cab6e70f13bce30d49be725627e0338edde4c4e09a8884fe91191100",
            "rewardAddress": "NQ46 U66M JNLD 0DJ7 0E9P Q7XR V9KV H976 813A",
            "signalData": null,
            "balance": 10100000000,
            "numStakers": 1,
            "inactivityFlag": null,
            "retired": false,
            "jailedFrom": null
        },
        "metadata": {
            "blockNumber": 816,
            "blockHash": "56289ca3533c411069962c8bc2ef4d87d614dbca01cdcba884ed3da4aa9be9be"
        }
    },
    "id": "test"
}
```
3. If `numStakers`  is `0` you do not have any stakers, therefore no payout has to be completed.
4. If `numStakers` is higher than `0` call `getStakersByValidatorAddress` for your validator. This should return an array of stakers that have delegated stake to your validator.
5. For each staker, calculate their stake percentage based of their `balance` compared to the total balance returned for the validator. Store this information.

## B - checkpoint block
A checkpoint block denotes finality on the chain. With each checkpoint block rewards are paid out to active validators. Important catch is that rewards always reflect the previous batch, not the current batch. That means that the last rewards for for example epoch 3 are paid out in the first batch of epoch 4.

For each checkpoint block in an epoch you want to get the rewards paid out to your validator reward address. You can do this by calling `getInherentsByBlockNumber` RPC call. You can do this once every epoch, for each batch or at any other interval. 

*Example:*

Given I want the rewards for batch 1, these are paid out in batch 2. With a batch size of `60` blocks the rewards for batch 1 are paid out in block `120`

```
{
    "jsonrpc": "2.0",
    "result": {
        "data": [
            {
                "type": "reward",
                "blockNumber": 120,
                "blockTime": 1725309410050,
                "validatorAddress": "NQ83 BPY4 JPJH 5B1Y NYKQ 32V1 84L4 YU35 1VTL",
                "target": "NQ46 Q7MG GCJK GTPC NR5A FHQL YCCF USGE JKYA",
                "value": 80271028,
                "hash": "558ae07d43269edf1409a56af1f38b98eff8d0de24e7fc241b11cd3ce7ea37ba"
            },
            {
                "type": "reward",
                "blockNumber": 120,
                "blockTime": 1725309410050,
                "validatorAddress": "NQ69 MH90 3M5H DFNU 8E84 53FX JSY6 XYQS N2CE",
                "target": "NQ48 PFG8 9808 K8Y6 P6T8 8BPA VCV6 MQ04 AHVU",
                "value": 91923588,
                "hash": "ec388480b475953c4fa293a63dc08010683f9b172aa509e68bac02a0e25e83b5"
            },
            {
                "type": "reward",
                "blockNumber": 120,
                "blockTime": 1725309410050,
                "validatorAddress": "NQ20 TSB0 DFSM UH9C 15GQ GAGJ TTE4 D3MA 859E",
                "target": "NQ46 U66M JNLD 0DJ7 0E9P Q7XR V9KV H976 813A",
                "value": 76386946,
                "hash": "75e0a7781e5b02399c7b82ba2330897ebe4ffe0b5d57ba7cbd4281b412bde588"
            },
            {
                "type": "reward",
                "blockNumber": 120,
                "blockTime": 1725309410050,
                "validatorAddress": "NQ79 VVKK SSCG HJUJ KFHV EA1Y NEJ6 6P7S ST56",
                "target": "NQ83 6L05 RT3P 6M3L 12GL LLP7 SUK0 1V71 4KQ8",
                "value": 82860416,
                "hash": "e47851d46d2c0ce1bfa425775f01f7b361effc2b44db831e00349f66a510cd7e"
            }
        ],
        "metadata": null
    },
    "id": "test"
}
```

In the above example there are 4 reward payouts to 4 different validators. The `validatorAddress`  is the validator address (obviously) and the `target`  is the reward address. `value` is the reward amount.

## C - payout
* In part `A` you have stored the stakers of your validator and their stake percentage
* In part `B` you have retrieved and stored all rewards for the epoch

You can now do payouts. When you do payouts is up to you. For each reward you want to:
* get the stake percentage for each staker for the epoch the reward was paid for
* calculate the cut the staker is owed
* deduct a pool fee
* store the amount owed
* you could either pay out the amount right away, or accumulate more payouts and pay them out at once with a single transaction.

Payouts are usually done by paying out in stake using an add stake transaction. You can either craft the transaction yourself, sign it offline and use `sendRawTransaction`  or use the RPC methods to do so. For the latter option you have to use a combination of `importRawKey`, `unlockAccount` and `sendStakeTransaction`
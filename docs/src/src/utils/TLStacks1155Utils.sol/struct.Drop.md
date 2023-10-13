# Drop
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/utils/TLStacks1155Utils.sol)

*stacks drop struct*


```solidity
struct Drop {
    DropType dropType;
    address payoutReceiver;
    uint256 initialSupply;
    uint256 supply;
    uint256 allowance;
    address currencyAddress;
    uint256 startTime;
    uint256 presaleDuration;
    uint256 presaleCost;
    bytes32 presaleMerkleRoot;
    uint256 publicDuration;
    uint256 publicCost;
    int256 decayRate;
}
```


# ITLStacks721Events
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/utils/TLStacks721Utils.sol)


## Events
### WethUpdated

```solidity
event WethUpdated(address indexed prevWeth, address indexed newWeth);
```

### ProtocolFeeUpdated

```solidity
event ProtocolFeeUpdated(address indexed newProtocolFeeReceiver, uint256 indexed newProtocolFee);
```

### DropConfigured

```solidity
event DropConfigured(address indexed nftAddress, Drop drop);
```

### DropUpdated

```solidity
event DropUpdated(address indexed nftAddress, Drop drop);
```

### DropClosed

```solidity
event DropClosed(address indexed nftAddress);
```

### Purchase

```solidity
event Purchase(
    address indexed nftAddress,
    address nftReceiver,
    address currencyAddress,
    uint256 amount,
    uint256 price,
    int256 decayRate,
    bool isPresale
);
```


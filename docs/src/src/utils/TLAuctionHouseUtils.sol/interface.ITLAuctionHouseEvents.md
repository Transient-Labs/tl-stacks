# ITLAuctionHouseEvents
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/utils/TLAuctionHouseUtils.sol)


## Events
### RoyaltyEngineUpdated

```solidity
event RoyaltyEngineUpdated(address indexed prevRoyaltyEngine, address indexed newRoyaltyEngine);
```

### WethUpdated

```solidity
event WethUpdated(address indexed prevWeth, address indexed newWeth);
```

### MinBidIncreaseUpdated

```solidity
event MinBidIncreaseUpdated(uint256 indexed newMinBidIncreasePerc, uint256 indexed newMinBidIncreaseLimit);
```

### ProtocolFeeUpdated

```solidity
event ProtocolFeeUpdated(
    address indexed newProtocolFeeReceiver, uint256 indexed newProtocolFeePerc, uint256 indexed newProtocolFeeLimit
);
```

### AuctionConfigured

```solidity
event AuctionConfigured(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Auction auction);
```

### AuctionCanceled

```solidity
event AuctionCanceled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId);
```

### AuctionSettled

```solidity
event AuctionSettled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Auction auction);
```

### AuctionBid

```solidity
event AuctionBid(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Auction auction);
```

### SaleConfigured

```solidity
event SaleConfigured(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Sale sale);
```

### SaleCanceled

```solidity
event SaleCanceled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId);
```

### SaleFulfilled

```solidity
event SaleFulfilled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Sale sale);
```


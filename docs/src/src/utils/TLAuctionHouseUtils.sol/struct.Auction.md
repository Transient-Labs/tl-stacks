# Auction
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/utils/TLAuctionHouseUtils.sol)

*Auction struct*


```solidity
struct Auction {
    address seller;
    address payoutReceiver;
    address currencyAddress;
    address highestBidder;
    uint256 highestBid;
    uint256 reservePrice;
    uint256 auctionOpenTime;
    uint256 startTime;
    uint256 duration;
}
```


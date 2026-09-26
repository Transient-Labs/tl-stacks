// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

enum ListingType {
    NOT_CONFIGURED,
    SCHEDULED_AUCTION,
    RESERVE_AUCTION,
    RESERVE_AUCTION_PLUS_BUY_NOW,
    BUY_NOW,
    PRIVATE_SALE
}

/// @dev The Listing struct contains general information about the sale on the auction house,
/// such as the type of sale, seller, currency, when the listing opens, and the pricing mechanics (based on type)
struct Listing {
    ListingType type_;
    bool zeroProtocolFee;
    address seller;
    address payoutReceiver;
    address currencyAddress;
    uint256 openTime;
    uint256 reservePrice;
    uint256 buyNowPrice;
    uint256 startTime;
    uint256 duration;
    address recipient;
    address highestBidder;
    uint256 highestBid;
    uint256 id;
}

interface ITLAuctionHouseEvents {
    event ProtocolFeeUpdated(address indexed newProtocolFeeReceiver, uint256 indexed newProtocolFee);
    event ProtocolFeeRemoved(address indexed nftAddress, uint256 indexed tokenId);
    event CreatorLookupUpdated(address indexed prevCreatorLookup, address indexed newCreatorLookup);
    event RoyaltyLookupUpdated(address indexed prevRoyaltyLookup, address indexed newRoyaltyLookup);

    event ListingConfigured(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing
    );
    event ListingCanceled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing);

    event AuctionBid(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing);
    event AuctionSettled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing);

    event BuyNowFulfilled(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, address recipient, Listing listing
    );

    event FundsCredited(address indexed account, address indexed currencyAddress, uint256 amount);
    event FundsClaimed(address indexed account, address indexed currencyAddress, address to, uint256 amount);
    event NftCredited(address indexed account, address indexed nftAddress, uint256 indexed tokenId);
    event NftClaimed(address indexed account, address indexed nftAddress, uint256 indexed tokenId, address to);
}

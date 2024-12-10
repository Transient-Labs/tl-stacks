// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

enum ListingType {
    NOT_CONFIGURED,
    SCHEDULED_AUCTION,
    RESERVE_AUCTION,
    RESERVE_AUCTION_PLUS_BUY_NOW,
    BUY_NOW
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
    uint256 id;
}

/// @dev The Auction struct contains information related to the auction progress itself,
/// while general information is stored in the listing
struct Auction {
    uint256 startTime;
    uint256 duration;
    address recipient;
    address highestBidder;
    uint256 highestBid;
}

interface ITLAuctionHouseEvents {
    event WethUpdated(address indexed prevWeth, address indexed newWeth);
    event ProtocolFeeUpdated(address indexed newProtocolFeeReceiver, uint256 indexed newProtocolFee);
    event CreatorLookupUpdated(address indexed prevCreatorLookup, address indexed newCreatorLookup);
    event RoyaltyLookupUpdated(address indexed prevRoyaltyLookup, address indexed newRoyaltyLookup);

    event ListingConfigured(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing, Auction auction
    );
    event ListingCanceled(address indexed sender, address indexed nftAddress, uint256 indexed tokenId);

    event AuctionBid(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing, Auction auction
    );
    event AuctionSettled(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, Listing listing, Auction auction
    );

    event BuyNowFulfilled(
        address indexed sender, address indexed nftAddress, uint256 indexed tokenId, address recipie, Listing listing
    );
}

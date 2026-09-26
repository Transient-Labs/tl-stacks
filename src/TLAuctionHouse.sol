// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable, Ownable2Step} from "@openzeppelin-contracts-5.6.1/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin-contracts-5.6.1/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";
import {SanctionsCompliance} from "./lib/SanctionsCompliance.sol";
import {CurrencyAllowlist} from "./lib/CurrencyAllowlist.sol";
import {ListingType, Listing, ListingConfig, ITLAuctionHouseEvents} from "./utils/TLAuctionHouseUtils.sol";
import {ICreatorLookup} from "./helpers/ICreatorLookup.sol";
import {IRoyaltyLookup} from "./helpers/IRoyaltyLookup.sol";

/// @title TLAuctionHouse
/// @notice Transient Labs Auction House for ERC-721 tokens
/// @author Transient Labs, Inc.
/// @custom:version-last-updated 2.8.0
contract TLAuctionHouse is
    Ownable2Step,
    Pausable,
    ReentrancyGuard,
    SanctionsCompliance,
    CurrencyAllowlist,
    TransferHelper,
    ITLAuctionHouseEvents
{
    /////////////////////////////////////////////////////////////////////
    // CONSTANTS
    /////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.8.0";
    uint256 public constant EXTENSION_TIME = 5 minutes;
    uint256 public constant BASIS = 10_000;
    uint256 public constant BID_INCREASE_BPS = 500; // 5% increase between bids
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 500; // 5% max protocol fee
    uint256 public constant MAX_ROYALTY_BPS = 1_000; // royalties can take at most 10% of the sale value
    uint256 public constant MAX_ROYALTY_RECIPIENTS = 10; // bounds gas spent on royalty payouts
    uint256 public constant MAX_AUCTION_DURATION = 30 days;
    uint256 public constant SETTLEMENT_GRACE_PERIOD = 7 days; // time after an auction ends before an unsettled auction can be canceled
    uint256 public constant PAYOUT_GAS_LIMIT = 1e5; // gas forwarded on ETH payouts before crediting instead, so a payee can't burn the gas needed to finish the call

    /////////////////////////////////////////////////////////////////////
    // STORAGE
    /////////////////////////////////////////////////////////////////////

    uint256 private _id; // listing id
    address public protocolFeeReceiver; // receives protocol fee
    uint256 public protocolFeeBps; // basis points for protocol fee
    ICreatorLookup public creatorLookup; // creator lookup contract
    IRoyaltyLookup public royaltyLookup; // royalty lookup contract

    mapping(address nftAddress => mapping(uint256 tokenId => Listing)) private _listings; // nft address -> token id -> listing
    mapping(address user => mapping(address currencyAddress => uint256)) public claimableFunds; // user address -> currency address -> amount that failed to send and can be claimed
    mapping(address nftAddress => mapping(uint256 tokenId => address)) public claimableNft; // nft address -> token id -> account that can claim the escrowed nft

    /////////////////////////////////////////////////////////////////////
    // ERRORS
    /////////////////////////////////////////////////////////////////////

    error InvalidListingType();
    error NotTokenOwner();
    error NotSeller();
    error ListingNotSetup();
    error AuctionStarted();
    error AuctionNotStarted();
    error AuctionNotEnded();
    error CannotBidYet();
    error CannotBuyYet();
    error InvalidRecipient();
    error BidTooLow();
    error AuctionEnded();
    error UnexpectedMsgValue();
    error InvalidProtocolFeeBps();
    error AlreadyListed();
    error InvalidPayoutReceiver();
    error InvalidDuration();
    error CurrencyMismatch();
    error ListingChanged();
    error PriceTooHigh();
    error NftTransferFailed();
    error NothingToClaim();
    error NotSellerOrBidder();
    error SettlementGracePeriodNotOver();
    error NotHighestBidder();

    /////////////////////////////////////////////////////////////////////
    // CONSTRUCTOR
    /////////////////////////////////////////////////////////////////////

    constructor(address initOwner, address initSanctionsOracle)
        Ownable(initOwner)
        Pausable()
        ReentrancyGuard()
        SanctionsCompliance(initSanctionsOracle)
    {}

    /////////////////////////////////////////////////////////////////////
    // PUBLIC FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to list an NFT for sale
    /// @dev Requirements
    ///      - only the token owner can list
    ///      - the token cannot already be listed
    ///      - the payout receiver cannot be the zero address or sanctioned
    ///      - the currency must be on the allowlist (ETH is always allowed)
    ///      - the auction duration cannot exceed `MAX_AUCTION_DURATION`
    ///      - private sales must specify a recipient that isn't the zero address or sanctioned
    ///      - the token is escrowed upon listing
    ///      - if the auction house isn't approved for the token, escrowing will fail, so no need to check for that explicitly
    /// @param config The listing configuration (see `ListingConfig`)
    function list(ListingConfig calldata config) external nonReentrant whenNotPaused {
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        _list(config);
    }

    /// @notice Function to list multiple NFTs for sale in a single transaction
    /// @dev Each listing has the same requirements as `list`, and if any listing fails, the whole batch reverts
    /// @param configs The listing configurations (see `ListingConfig`)
    function batchList(ListingConfig[] calldata configs) external nonReentrant whenNotPaused {
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        for (uint256 i = 0; i < configs.length; ++i) {
            _list(configs[i]);
        }
    }

    /// @notice Function to update a listing without having to cancel and relist
    /// @dev Requirements
    ///      - only the seller of the listing can update
    ///      - the seller cannot be sanctioned
    ///      - the auction cannot have been bid on (use `updatePayoutReceiver` to change the payout receiver after bids)
    ///      - the listing type and currency cannot change
    ///      - the new configuration has the same requirements as `list`
    ///      - the listing gets a new id, so pending bids and buys signed against the previous terms revert
    ///      - a protocol fee removed by the contract owner stays removed
    /// @param config The new listing configuration (see `ListingConfig`)
    function updateListing(ListingConfig calldata config) external nonReentrant whenNotPaused {
        // cache data
        Listing memory listing = _listings[config.nftAddress][config.tokenId];

        // revert if caller is not seller
        // this also catches if the nft is not listed, as the seller is the zero address
        if (msg.sender != listing.seller) revert NotSeller();
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // terms can't change once the auction has been bid on
        if (listing.highestBidder != address(0)) revert AuctionStarted();

        // listing type and currency are fixed
        if (config.type_ != listing.type_) revert InvalidListingType();
        if (config.currencyAddress != listing.currencyAddress) revert CurrencyMismatch();

        // build and save the updated listing
        listing = _buildListing(config, listing.seller, listing.zeroProtocolFee);
        _listings[config.nftAddress][config.tokenId] = listing;

        emit ListingUpdated(msg.sender, config.nftAddress, config.tokenId, listing);
    }

    /// @notice Function to update the payout receiver for a listing
    /// @dev Requirements
    ///      - only the seller of the listing can update
    ///      - the seller cannot be sanctioned
    ///      - the new payout receiver cannot be the zero address or sanctioned
    ///      - can be called at any point before the listing is settled or canceled, including after bids
    ///      - the listing id does not change, as the terms for buyers and bidders are unaffected
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param newPayoutReceiver The new address that will receive payout for the sale
    function updatePayoutReceiver(address nftAddress, uint256 tokenId, address newPayoutReceiver)
        external
        whenNotPaused
    {
        Listing storage listing = _listings[nftAddress][tokenId];

        // revert if caller is not seller
        // this also catches if the nft is not listed, as the seller is the zero address
        if (msg.sender != listing.seller) revert NotSeller();
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        if (!_isValidRecipient(newPayoutReceiver)) revert InvalidPayoutReceiver();

        listing.payoutReceiver = newPayoutReceiver;

        emit ListingUpdated(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to cancel a listing
    /// @dev Requirements
    ///      - only the seller of the listing can delist
    ///      - the listing must be active
    ///      - the auction cannot have been started when delisting
    /// @dev Not gated by pause, since it only returns an escrowed nft to a seller with no bids to honor
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function delist(address nftAddress, uint256 tokenId) external nonReentrant {
        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // revert if caller is not seller
        // this also catches if the nft is not listing, as the seller is the zero address
        if (msg.sender != listing.seller) revert NotSeller();

        // escrowed nfts of sanctioned sellers stay frozen
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // check if auction has been bid on (this should always pass if listing type is BUY_NOW)
        if (listing.highestBidder != address(0)) revert AuctionStarted();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // transfer token back to seller
        _transferNft(nftAddress, tokenId, address(this), listing.seller);

        emit ListingCanceled(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to bid on a token that has an auction configured
    /// @dev Requirements
    ///      - msg.sender can't be a sanctioned address
    ///      - a listing must be configured as an auction
    ///      - the listing id must match `expectedListingId`, so a delisted and relisted token (e.g. with a longer
    ///        duration) can't be bid on with a transaction signed against the previous listing
    ///      - the listing currency must match `currencyAddress`
    ///      - the block timestamp is past the listing open time
    ///      - the bid can't be too low (non-zero and at least the reserve price for first bid or under next bid for subsequent bids)
    ///      - the auction can't have ended
    ///      - the funds sent must match `amount` exactly when bidding
    ///      - the previous bid is sent back (or credited to `claimableFunds` if the transfer fails)
    ///      - if bidding with ERC-20 tokens, no ETH is allowed to be sent
    ///      - if a bid comes within `EXTENSION_TIME`, extend the auction back to `EXTENSION_TIME`
    ///      - the bidder receives the nft if they win, and any refund if they are outbid (`recipient` in the listing
    ///        is always the highest bidder)
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param currencyAddress The currency the bidder expects to pay in (zero address == ETH)
    /// @param amount The amount to bid
    /// @param expectedListingId The listing id the bidder expects to bid on
    function bid(
        address nftAddress,
        uint256 tokenId,
        address currencyAddress,
        uint256 amount,
        uint256 expectedListingId
    ) external payable nonReentrant whenNotPaused {
        // check sender
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];
        uint256 previousBid = listing.highestBid;
        address previousBidder = listing.highestBidder;
        uint256 auctionEndTime = listing.startTime + listing.duration;

        // check the listing type
        if (!_isAuction(listing.type_)) revert InvalidListingType();

        // protect the bidder from the listing changing between signing and execution
        if (listing.id != expectedListingId) revert ListingChanged();
        if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();

        // cannot bid if prior to listing.openTime
        if (block.timestamp < listing.openTime) revert CannotBidYet();

        // check constraints on first bid versus other bids
        if (previousBidder == address(0)) {
            // first bid cannot be zero or under reserve price
            if (amount == 0 || amount < listing.reservePrice) revert BidTooLow();

            // set start time if reserve auction
            if (
                listing.type_ == ListingType.RESERVE_AUCTION
                    || listing.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW
            ) {
                listing.startTime = block.timestamp;
                auctionEndTime = listing.startTime + listing.duration;
            }

            // if scheduled auction, make sure that can't bid on a token that has gone past the scheduled duration without bids
            if (listing.type_ == ListingType.SCHEDULED_AUCTION) {
                if (block.timestamp > auctionEndTime) revert AuctionEnded();
            }
        } else {
            // subsequent bids
            // cannot bid after auction is ended
            if (block.timestamp > auctionEndTime) revert AuctionEnded();

            // ensure amount being bid is greater than minimum next bid
            if (amount < _calcNextBid(listing.highestBid)) revert BidTooLow();
        }

        // update auction, extending duration if needed
        listing.highestBid = amount;
        listing.highestBidder = msg.sender;
        listing.recipient = msg.sender;
        uint256 timeRemaining = auctionEndTime - block.timestamp; // checks for being past auction end time avoid underflow issues here
        if (timeRemaining < EXTENSION_TIME) {
            listing.duration += EXTENSION_TIME - timeRemaining;
        }

        // save listing
        _listings[nftAddress][tokenId] = listing;

        // escrow the bid
        _escrowFunds(listing.currencyAddress, amount);

        // return previous bid, if it's a subsequent bid
        _payout(previousBidder, listing.currencyAddress, previousBid);

        emit AuctionBid(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function for the highest bidder to add to their bid
    /// @dev Requirements
    ///      - msg.sender can't be a sanctioned address
    ///      - a listing must be configured as an auction
    ///      - the listing id must match `expectedListingId`, so a top up signed against a previous listing of the
    ///        token can't land on a new listing where msg.sender is also the highest bidder (e.g. smart accounts
    ///        whose transactions can execute out of order)
    ///      - msg.sender must be the highest bidder
    ///      - the auction can't have ended
    ///      - `amount` must be non-zero and the funds sent must match `amount` exactly
    ///      - if topping up with ERC-20 tokens, no ETH is allowed to be sent
    ///      - topping up never extends the auction, so the highest bidder can't hold an auction open indefinitely
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param amount The amount to add to the current bid
    /// @param expectedListingId The listing id the bidder expects to top up their bid on
    function topUpBid(address nftAddress, uint256 tokenId, uint256 amount, uint256 expectedListingId)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        // check sender
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check the listing type
        if (!_isAuction(listing.type_)) revert InvalidListingType();

        // protect the bidder from the listing changing between signing and execution
        if (listing.id != expectedListingId) revert ListingChanged();

        // only the highest bidder can top up (this also catches auctions without bids)
        if (msg.sender != listing.highestBidder) revert NotHighestBidder();

        // cannot top up after auction is ended
        if (block.timestamp > listing.startTime + listing.duration) revert AuctionEnded();

        // top up must be non-zero
        if (amount == 0) revert BidTooLow();

        // update and save the bid
        listing.highestBid += amount;
        _listings[nftAddress][tokenId].highestBid = listing.highestBid;

        // escrow the additional funds
        _escrowFunds(listing.currencyAddress, amount);

        emit AuctionBidToppedUp(msg.sender, nftAddress, tokenId, amount, listing);
    }

    /// @notice Function to settle an auction
    /// @dev Requirements
    ///      - can be called by anyone on the blockchain
    ///      - the listing must be configured as an auction
    ///      - the auction must have been started AND ended
    ///      - the seller and highest bidder cannot be sanctioned
    ///      - the nft is delivered to the highest bidder before any funds are released to the seller
    ///      - royalties are paid out on secondary sales, where the creator of the token is not the seller
    /// @dev Settlement either fully completes or reverts. If an auction can't be settled, the seller or highest bidder
    ///      can cancel it after `SETTLEMENT_GRACE_PERIOD` via `cancelUnsettledAuction`.
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function settleAuction(address nftAddress, uint256 tokenId) external nonReentrant whenNotPaused {
        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check to make sure the listing is the right type
        if (!_isAuction(listing.type_)) revert InvalidListingType();

        // check that auction was bid on
        if (listing.highestBidder == address(0)) revert AuctionNotStarted();

        // ensure auction is ended
        if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();

        // re-check sanctions, as any party may have been sanctioned since listing or bidding
        if (_isSanctioned(listing.seller)) revert SanctionedAddress();
        if (_isSanctioned(listing.highestBidder)) revert SanctionedAddress();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // deliver nft and distribute the winning bid
        _completeSale(nftAddress, tokenId, listing, listing.highestBidder, listing.highestBid);

        emit AuctionSettled(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to cancel an auction that couldn't be settled
    /// @dev Requirements
    ///      - only the seller or highest bidder can cancel
    ///      - the listing must be configured as an auction and have been bid on
    ///      - the auction must have ended more than `SETTLEMENT_GRACE_PERIOD` ago without being settled
    /// @dev The highest bid is credited to the bidder's `claimableFunds` balance and the nft is held for the seller to
    ///      claim via `claimNft`. No external calls are made, so a misbehaving nft or payee can't block this.
    ///      Anything owed to a sanctioned address stays frozen until the address is no longer sanctioned.
    /// @dev Not gated by pause, since it only moves escrowed assets into `claimableFunds` and `claimableNft`
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function cancelUnsettledAuction(address nftAddress, uint256 tokenId) external nonReentrant {
        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check to make sure the listing is the right type
        if (!_isAuction(listing.type_)) revert InvalidListingType();

        // check that auction was bid on
        if (listing.highestBidder == address(0)) revert AuctionNotStarted();

        // only the parties to the sale can cancel
        if (msg.sender != listing.seller && msg.sender != listing.highestBidder) revert NotSellerOrBidder();

        // ensure the grace period for settlement has passed
        if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD) {
            revert SettlementGracePeriodNotOver();
        }

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // refund bidder and hold nft for the seller
        _credit(listing.highestBidder, listing.currencyAddress, listing.highestBid);
        claimableNft[nftAddress][tokenId] = listing.seller;
        emit NftCredited(listing.seller, nftAddress, tokenId);

        emit ListingCanceled(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to buy a token at a fixed price
    /// @dev Requirements
    ///      - msg.sender and recipient cannot be sanctioned
    ///      - recipient cannot be the zero address
    ///      - listing must be configured as a reserve auction with a buy now price, a buy now, or a private sale
    ///      - for private sales, `recipient` must be the recipient set by the seller (anyone can pay)
    ///      - the listing id must match `expectedListingId`, so a delisted and relisted token can't be bought with a
    ///        transaction signed against the previous listing
    ///      - the listing currency must match `currencyAddress` and the buy now price cannot exceed `maxPrice`
    ///      - if it's an auction + buy now, the auction cannot be started
    ///      - the listing must be open
    ///      - the nft must be delivered to the recipient before any funds are released to the seller
    ///      - royalties are paid out for secondary sales, where the creator of the token is not the seller
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param recipient The recipient that will receive the NFT
    /// @param currencyAddress The currency the buyer expects to pay in (zero address == ETH)
    /// @param maxPrice The maximum price the buyer is willing to pay
    /// @param expectedListingId The listing id the buyer expects to buy from
    function buyNow(
        address nftAddress,
        uint256 tokenId,
        address recipient,
        address currencyAddress,
        uint256 maxPrice,
        uint256 expectedListingId
    ) external payable nonReentrant whenNotPaused {
        // check sender & recipient
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        if (!_isValidRecipient(recipient)) revert InvalidRecipient();

        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check the listing type
        if (!_hasBuyNow(listing.type_)) revert InvalidListingType();

        // private sales can only be delivered to the recipient chosen by the seller
        if (listing.type_ == ListingType.PRIVATE_SALE && recipient != listing.recipient) revert InvalidRecipient();

        // can't buy from sanctioned sellers
        if (_isSanctioned(listing.seller)) revert SanctionedAddress();

        // protect the buyer from the listing changing between signing and execution
        if (listing.id != expectedListingId) revert ListingChanged();
        if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();
        if (listing.buyNowPrice > maxPrice) revert PriceTooHigh();

        // cannot buy if an auction is live
        if (listing.highestBidder != address(0)) revert AuctionStarted();

        // cannot buy if prior to listing.openTime
        if (block.timestamp < listing.openTime) revert CannotBuyYet();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // escrow the payment from the sender (not the recipient)
        _escrowFunds(listing.currencyAddress, listing.buyNowPrice);

        // deliver nft and distribute the payment (reverting returns the buyer's funds)
        _completeSale(nftAddress, tokenId, listing, recipient, listing.buyNowPrice);

        emit BuyNowFulfilled(msg.sender, nftAddress, tokenId, recipient, listing);
    }

    /// @notice Function to claim funds that failed to be sent to the caller
    /// @dev Requirements
    ///      - msg.sender and `to` cannot be sanctioned
    ///      - `to` cannot be the zero address
    ///      - msg.sender must have a non-zero `claimableFunds` balance for `currencyAddress`
    /// @dev Not gated by pause, since funds can only be credited through pausable functions
    /// @param currencyAddress The currency to claim (zero address == ETH)
    /// @param to The address to send the funds to, which allows the intended recipient to redirect funds
    function claimFunds(address currencyAddress, address to) external nonReentrant {
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        if (!_isValidRecipient(to)) revert InvalidRecipient();

        uint256 amount = claimableFunds[msg.sender][currencyAddress];
        if (amount == 0) revert NothingToClaim();

        // reset claimable funds
        claimableFunds[msg.sender][currencyAddress] = 0;

        if (currencyAddress == address(0)) {
            _safeTransferETH(to, amount);
        } else {
            _safeTransferERC20(to, currencyAddress, amount);
        }

        emit FundsClaimed(msg.sender, currencyAddress, to, amount);
    }

    /// @notice Function to claim an escrowed nft that couldn't be returned to the caller
    /// @dev Requirements
    ///      - msg.sender and `to` cannot be sanctioned
    ///      - `to` cannot be the zero address
    ///      - msg.sender must be able to claim the nft
    /// @dev Not gated by pause, since nfts can only be credited through pausable functions
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param to The address to send the nft to
    function claimNft(address nftAddress, uint256 tokenId, address to) external nonReentrant {
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        if (!_isValidRecipient(to)) revert InvalidRecipient();
        if (claimableNft[nftAddress][tokenId] != msg.sender) revert NothingToClaim();

        delete claimableNft[nftAddress][tokenId];
        _transferNft(nftAddress, tokenId, address(this), to);

        emit NftClaimed(msg.sender, nftAddress, tokenId, to);
    }

    /////////////////////////////////////////////////////////////////////
    // ADMIN FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to set the protocol fee settings
    /// @dev Requires owner
    /// @dev The new protocol fee bps cannot exceed `MAX_PROTOCOL_FEE_BPS`
    /// @param newProtocolFeeReceiver The new address to receive protocol fees
    /// @param newProtocolFeeBps The new bps for the protocol fee
    function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFeeBps) external onlyOwner {
        if (!_isValidRecipient(newProtocolFeeReceiver)) revert InvalidRecipient();
        if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();

        protocolFeeReceiver = newProtocolFeeReceiver;
        protocolFeeBps = newProtocolFeeBps;

        emit ProtocolFeeUpdated(newProtocolFeeReceiver, newProtocolFeeBps);
    }

    /// @notice Function to set the sanctions oracle
    /// @dev Requires owner
    /// @param newOracle The new sanctions oracle address (zero address disables)
    function setSanctionsOracle(address newOracle) external onlyOwner {
        _updateSanctionsOracle(newOracle);
    }

    /// @notice Function to add or remove an ERC-20 currency from the allowlist
    /// @dev Requires owner
    /// @dev Removing a currency only blocks new sales from using it, existing sales are unaffected
    /// @dev Only allow standard ERC-20 tokens. Escrow and payout accounting assume balances held by this contract
    ///      only change through its own transfers, and payouts don't account for transfer fees, so rebasing,
    ///      fee-on-transfer, and other balance-altering tokens must never be allowed. A negative rebase would leave
    ///      escrowed bids and `claimableFunds` underfunded. Low-decimal tokens should also be avoided so that bid
    ///      increments stay meaningful.
    /// @param currencyAddress The ERC-20 currency address
    /// @param allowed Boolean indicating if the currency is allowed
    function setCurrencyAllowed(address currencyAddress, bool allowed) external onlyOwner {
        _setCurrencyAllowed(currencyAddress, allowed);
    }

    /// @notice Function to update the creator lookup contract
    /// @dev Requires owner
    /// @param newCreatorLookupAddress The helper contract address for looking up a token creator
    function setCreatorLookup(address newCreatorLookupAddress) external onlyOwner {
        address prevCreatorLookup = address(creatorLookup);
        creatorLookup = ICreatorLookup(newCreatorLookupAddress);

        emit CreatorLookupUpdated(prevCreatorLookup, newCreatorLookupAddress);
    }

    /// @notice Function to update the royalty lookup contract
    /// @dev Requires owner
    /// @param newRoyaltyLookupAddress The helper contract address for looking up token royalties
    function setRoyaltyLookup(address newRoyaltyLookupAddress) external onlyOwner {
        address prevRoyaltyLookup = address(royaltyLookup);
        royaltyLookup = IRoyaltyLookup(newRoyaltyLookupAddress);

        emit RoyaltyLookupUpdated(prevRoyaltyLookup, newRoyaltyLookupAddress);
    }

    /// @notice Function to pause the contract
    /// @dev Requires owner
    /// @param status The boolean flag for the paused status
    function pause(bool status) external onlyOwner {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Function to remove protocol fee from a specific listing
    /// @dev Requires owner
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function removeProtocolFee(address nftAddress, uint256 tokenId) external onlyOwner {
        if (_listings[nftAddress][tokenId].type_ == ListingType.NOT_CONFIGURED) revert InvalidListingType();

        _listings[nftAddress][tokenId].zeroProtocolFee = true;

        emit ProtocolFeeRemoved(nftAddress, tokenId);
    }

    /////////////////////////////////////////////////////////////////////
    // VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to get a specific listing
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        Listing memory listing = _listings[nftAddress][tokenId];

        return listing;
    }

    /// @notice Function to get the next bid amount for a token
    /// @dev Before the first bid, this is the reserve price (or 1, as bids can't be zero)
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getNextBid(address nftAddress, uint256 tokenId) external view returns (uint256) {
        Listing memory listing = _listings[nftAddress][tokenId];
        if (listing.highestBidder == address(0)) return Math.max(listing.reservePrice, 1);

        return _calcNextBid(listing.highestBid);
    }

    /// @notice Function to understand if the sale is a primary or secondary sale
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getIfPrimarySale(address nftAddress, uint256 tokenId) external view returns (bool) {
        Listing memory listing = _listings[nftAddress][tokenId];
        return _isPrimarySale(nftAddress, tokenId, listing.seller);
    }

    /// @notice Function to get the royalty amounts that will be paid on a secondary sale
    /// @dev Capped the same way as royalties paid out on a sale (see `_capRoyalties`). A royalty payable to this
    ///      contract is omitted because it owns listed NFTs only while they are in escrow.
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param value The value to check against
    function getRoyalty(address nftAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory, uint256[] memory)
    {
        if (address(royaltyLookup).code.length == 0) return (new address payable[](0), new uint256[](0));
        try royaltyLookup.getRoyaltyView(nftAddress, tokenId, value) returns (
            address payable[] memory recipients, uint256[] memory amounts
        ) {
            return _capRoyalties(recipients, amounts, value);
        } catch {
            return (new address payable[](0), new uint256[](0));
        }
    }

    /////////////////////////////////////////////////////////////////////
    // HELPER FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Internal function to check if an nft recipient is valid
    /// @dev Returns false if the recipient is sanctioned or if it is the zero address
    function _isValidRecipient(address recipient) private view returns (bool) {
        if (recipient == address(0)) return false;
        if (_isSanctioned(recipient)) return false;
        return true;
    }

    /// @notice Internal function to check if a listing type is an auction
    function _isAuction(ListingType type_) private pure returns (bool) {
        return type_ == ListingType.SCHEDULED_AUCTION || type_ == ListingType.RESERVE_AUCTION
            || type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW;
    }

    /// @notice Internal function to check if a listing type can be bought at a fixed price
    function _hasBuyNow(ListingType type_) private pure returns (bool) {
        return type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW || type_ == ListingType.BUY_NOW
            || type_ == ListingType.PRIVATE_SALE;
    }

    /// @notice Internal function to list an nft for sale
    /// @dev See `list` for requirements. The caller must check that msg.sender isn't sanctioned.
    function _list(ListingConfig calldata config) private {
        if (!_isCurrencyAllowed(config.currencyAddress)) revert CurrencyNotAllowed();

        // explicitly block relisting, since a non-standard nft could report the wrong owner and overwrite a live listing
        if (_listings[config.nftAddress][config.tokenId].type_ != ListingType.NOT_CONFIGURED) revert AlreadyListed();

        // check that the sender owns the token
        if (IERC721(config.nftAddress).ownerOf(config.tokenId) != msg.sender) revert NotTokenOwner();

        // build and set listing
        Listing memory listing = _buildListing(config, msg.sender, false);
        _listings[config.nftAddress][config.tokenId] = listing;

        // escrow token, should revert if contract isn't approved
        _transferNft(config.nftAddress, config.tokenId, msg.sender, address(this));

        emit ListingConfigured(msg.sender, config.nftAddress, config.tokenId, listing);
    }

    /// @notice Internal function to validate a listing configuration and build a listing with a new id
    /// @dev Fields that don't apply to the listing type are zeroed out
    /// @param config The listing configuration
    /// @param seller The seller of the listing
    /// @param zeroProtocolFee Whether the protocol fee is removed for the listing
    function _buildListing(ListingConfig calldata config, address seller, bool zeroProtocolFee)
        private
        returns (Listing memory listing)
    {
        if (!_isValidRecipient(config.payoutReceiver)) revert InvalidPayoutReceiver();

        // if openTime is in a previous block, set to the current block timestamp
        uint256 openTime = config.openTime < block.timestamp ? block.timestamp : config.openTime;

        listing = Listing({
            type_: config.type_,
            zeroProtocolFee: zeroProtocolFee,
            seller: seller,
            payoutReceiver: config.payoutReceiver,
            currencyAddress: config.currencyAddress,
            openTime: openTime,
            reservePrice: config.reservePrice,
            buyNowPrice: config.buyNowPrice,
            startTime: 0,
            duration: config.auctionDuration,
            recipient: address(0),
            highestBidder: address(0),
            highestBid: 0,
            id: ++_id
        });

        // adjust listing based on listing type
        ListingType type_ = config.type_;
        if (type_ == ListingType.SCHEDULED_AUCTION) {
            listing.startTime = openTime;
            listing.buyNowPrice = 0;
        } else if (type_ == ListingType.RESERVE_AUCTION) {
            listing.buyNowPrice = 0;
        } else if (type_ == ListingType.BUY_NOW) {
            listing.reservePrice = 0;
            listing.duration = 0;
        } else if (type_ == ListingType.PRIVATE_SALE) {
            if (!_isValidRecipient(config.recipient)) revert InvalidRecipient();
            listing.reservePrice = 0;
            listing.duration = 0;
            listing.recipient = config.recipient;
        } else if (type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW) {
            // uses every pricing field, so nothing to adjust
            // note: forge coverage reports this branch as missed since the block has no statements, but it is tested
        } else {
            revert InvalidListingType();
        }
        if (listing.duration > MAX_AUCTION_DURATION) revert InvalidDuration();
    }

    /// @notice Internal function to calculate the next bid price
    /// @dev The increase rounds up so it is never below `BID_INCREASE_BPS`, even for low-decimal currencies. Only
    ///      called with a non-zero `currentBid`, so the increase is always at least 1.
    /// @param currentBid The current bid
    /// @return nextBid The next bid
    function _calcNextBid(uint256 currentBid) private pure returns (uint256 nextBid) {
        return currentBid + Math.mulDiv(currentBid, BID_INCREASE_BPS, BASIS, Math.Rounding.Ceil);
    }

    /// @notice Internal function to escrow funds from msg.sender for a bid or purchase
    /// @dev ETH must be sent as exactly `amount`, and no ETH can be sent along with an ERC-20 payment
    function _escrowFunds(address currencyAddress, uint256 amount) private {
        if (currencyAddress == address(0)) {
            if (msg.value != amount) revert UnexpectedMsgValue();
        } else {
            if (msg.value != 0) revert UnexpectedMsgValue();
            _safeTransferFromERC20(msg.sender, address(this), currencyAddress, amount);
        }
    }

    /// @notice Internal function to transfer an nft into or out of escrow
    /// @dev Uses `transferFrom` so that the recipient cannot reject the transfer
    /// @dev Verifies ownership afterwards, reverting if the nft didn't actually transfer
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param from The address to transfer the nft from
    /// @param to The address to transfer the nft to
    function _transferNft(address nftAddress, uint256 tokenId, address from, address to) private {
        IERC721(nftAddress).transferFrom(from, to, tokenId);
        if (IERC721(nftAddress).ownerOf(tokenId) != to) revert NftTransferFailed();
    }

    /// @notice Internal function to determine if a sale is a primary sale (seller is the creator)
    /// @dev If the creator lookup is unset or fails, the sale is treated as secondary so royalties are still paid
    /// @dev Trusts `creatorLookup` as the source of creator identity. With the default `CreatorLookup`, the creator
    ///      is the collection's current owner, so any sale by the collection owner skips royalties, even if the
    ///      royalty goes to someone else (e.g. a collaborator split, or a multi-artist collection)
    function _isPrimarySale(address nftAddress, uint256 tokenId, address seller) private view returns (bool) {
        if (address(creatorLookup).code.length == 0) return false;
        try creatorLookup.getCreator(nftAddress, tokenId) returns (address creator) {
            return creator == seller;
        } catch {
            return false;
        }
    }

    /// @notice Internal function to credit funds that couldn't be sent, to be claimed later
    function _credit(address account, address currencyAddress, uint256 amount) private {
        if (amount == 0) return;
        claimableFunds[account][currencyAddress] += amount;

        emit FundsCredited(account, currencyAddress, amount);
    }

    /// @notice Internal function to abstract payouts when settling a listing
    /// @dev Never reverts: if `to` is sanctioned or the transfer fails, the funds are credited to `to` to be claimed
    function _payout(address to, address currencyAddress, uint256 value) private {
        if (to == address(0) || value == 0) return;

        if (_isSanctioned(to)) {
            _credit(to, currencyAddress, value);
            return;
        }

        bool success;
        if (currencyAddress == address(0)) {
            success = _trySafeTransferETH(to, value, PAYOUT_GAS_LIMIT);
        } else {
            success = _trySafeTransferERC20(to, currencyAddress, value);
        }
        if (!success) _credit(to, currencyAddress, value);
    }

    /// @notice Internal function to cap royalties to what is paid out on a sale
    /// @dev Keeps at most `MAX_ROYALTY_RECIPIENTS` recipients and at most `MAX_ROYALTY_BPS` of `value` in total.
    ///      Recipients are paid in order, and once the cap is reached the remaining amounts are reduced to fit.
    /// @dev The zero address and this escrow contract get nothing, leaving their shares with the payout receiver
    /// @dev Returns empty arrays if the array lengths don't match
    function _capRoyalties(address payable[] memory recipients, uint256[] memory amounts, uint256 value)
        private
        view
        returns (address payable[] memory cappedRecipients, uint256[] memory cappedAmounts)
    {
        if (recipients.length != amounts.length) return (cappedRecipients, cappedAmounts);
        uint256 numRecipients = Math.min(recipients.length, MAX_ROYALTY_RECIPIENTS);
        cappedRecipients = new address payable[](numRecipients);
        cappedAmounts = new uint256[](numRecipients);
        uint256 royaltyBudget = value * MAX_ROYALTY_BPS / BASIS;
        for (uint256 i = 0; i < numRecipients; ++i) {
            if (recipients[i] == address(0) || recipients[i] == address(this)) continue;
            cappedRecipients[i] = recipients[i];
            cappedAmounts[i] = Math.min(amounts[i], royaltyBudget);
            royaltyBudget -= cappedAmounts[i];
        }
    }

    /// @notice Internal function to determine royalties before transferring the NFT
    /// @dev Royalties are capped by `_capRoyalties`; lookup failures leave the full sale value with the seller
    function _quoteRoyalties(address nftAddress, uint256 tokenId, uint256 value)
        private
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        if (address(royaltyLookup).code.length == 0) return (recipients, amounts);
        try royaltyLookup.getRoyalty(nftAddress, tokenId, value) returns (
            address payable[] memory r, uint256[] memory a
        ) {
            return _capRoyalties(r, a, value);
        } catch {
            // do nothing if royalty lookup call fails
        }
    }

    /// @notice Internal function to complete a sale/auction, delivering the nft and then distributing `value`
    /// @dev The listing must already be deleted. Royalties are quoted before the NFT moves, but the NFT is delivered
    ///      before any funds are released. A royalty payable to the escrow owner is omitted.
    function _completeSale(
        address nftAddress,
        uint256 tokenId,
        Listing memory listing,
        address recipient,
        uint256 value
    ) private {
        address payable[] memory royaltyRecipients = new address payable[](0);
        uint256[] memory royaltyAmounts = new uint256[](0);
        if (!_isPrimarySale(nftAddress, tokenId, listing.seller)) {
            (royaltyRecipients, royaltyAmounts) = _quoteRoyalties(nftAddress, tokenId, value);
        }

        _transferNft(nftAddress, tokenId, address(this), recipient);

        uint256 remainingValue = value;

        // take protocol fee (if not zeroed by contract owner)
        if (!listing.zeroProtocolFee) {
            uint256 protocolFee = value * protocolFeeBps / BASIS;
            remainingValue -= protocolFee;
            _payout(protocolFeeReceiver, listing.currencyAddress, protocolFee);
        }

        // pay the royalties quoted before transfer, based on the full sale value
        // can't underflow since `MAX_PROTOCOL_FEE_BPS` + `MAX_ROYALTY_BPS` is less than `BASIS`
        for (uint256 i = 0; i < royaltyRecipients.length; ++i) {
            remainingValue -= royaltyAmounts[i];
            _payout(royaltyRecipients[i], listing.currencyAddress, royaltyAmounts[i]);
        }

        // pay remaining amount to payout receiver (set by the seller)
        _payout(listing.payoutReceiver, listing.currencyAddress, remainingValue);
    }
}

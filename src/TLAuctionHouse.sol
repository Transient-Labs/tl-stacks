// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts-5.0.2/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.0.2/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin-contracts-5.0.2/token/ERC721/IERC721.sol";
import {TransferHelper} from "tl-sol-tools-3.1.4/payments/TransferHelper.sol";
import {SanctionsCompliance} from "tl-sol-tools-3.1.4/payments/SanctionsCompliance.sol";
import {ListingType, Listing, ITLAuctionHouseEvents} from "./utils/TLAuctionHouseUtils.sol";
import {ICreatorLookup} from "./helpers/ICreatorLookup.sol";
import {IRoyaltyLookup} from "./helpers/IRoyaltyLookup.sol";

/// @title TLAuctionHouse
/// @notice Transient Labs Auction House for ERC-721 tokens
/// @author transientlabs.xyz
/// @custom:version-last-updated 2.6.0
contract TLAuctionHouse is
    Ownable,
    Pausable,
    ReentrancyGuard,
    SanctionsCompliance,
    TransferHelper,
    ITLAuctionHouseEvents
{
    ///////////////////////////////////////////////////////////////////////////
    /// CONSTANTS
    ///////////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.6.0";
    uint256 public constant EXTENSION_TIME = 5 minutes;
    uint256 public constant BASIS = 10_000;
    uint256 public constant BID_INCREASE_BPS = 500; // 5% increase between bids

    ///////////////////////////////////////////////////////////////////////////
    /// STATE VARIABLES
    ///////////////////////////////////////////////////////////////////////////

    uint256 private _id; // listing id
    address public protocolFeeReceiver; // receives protocol fee
    uint256 public protocolFeeBps; // basis points for protocol fee
    address public weth; // weth address
    ICreatorLookup public creatorLookup; // creator lookup contract
    IRoyaltyLookup public royaltyLookup; // royalty lookup contract

    mapping(address => mapping(uint256 => Listing)) private _listings; // nft address -> token id -> listing

    ///////////////////////////////////////////////////////////////////////////
    /// ERRORS
    ///////////////////////////////////////////////////////////////////////////

    error InvalidListingType();
    error NotTokenOwner();
    error TokenNotTransferred();
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

    ///////////////////////////////////////////////////////////////////////////
    /// CONSTRUCTOR
    ///////////////////////////////////////////////////////////////////////////

    constructor(address initOwner, address initSanctionsOracle)
        Ownable(initOwner)
        Pausable()
        ReentrancyGuard()
        SanctionsCompliance(initSanctionsOracle)
    {}

    ///////////////////////////////////////////////////////////////////////////
    /// PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Function to list an NFT for sale
    /// @dev Requirements
    ///      - only the token owner can list
    ///      - the token is escrowed upon listing
    ///      - if the auction house isn't approved for the token, escrowing will fail, so no need to check for that explicitly
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param type_ The ListingType
    /// @param payoutReceiver The address that will receive payout for the sale
    /// @param currencyAddress The address of the currency to use (zero address == ETH)
    /// @param openTime The time at which the listing will open (if in the past, defaults to current block timestamp)
    /// @param reservePrice The reserve price for the auction (if part of the listing type)
    /// @param auctionDuration The duration of the auction
    /// @param buyNowPrice The price at which the token can be instantly bought if the listing if properly configured for this
    function list(
        address nftAddress,
        uint256 tokenId,
        ListingType type_,
        address payoutReceiver,
        address currencyAddress,
        uint256 openTime,
        uint256 reservePrice,
        uint256 auctionDuration,
        uint256 buyNowPrice
    ) external whenNotPaused nonReentrant {
        // check for sanctioned addresses
        _isSanctioned(msg.sender, true);
        _isSanctioned(payoutReceiver, true);

        // check that the sender owns the token
        IERC721 nftContract = IERC721(nftAddress);
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner(); // once listed, can't list again as the msg.sender wouldn't be the owner

        // if openTime is in a previous block, set to the current block timestamp
        if (openTime < block.timestamp) {
            openTime = block.timestamp;
        }

        // create listing
        uint256 id = ++_id;
        Listing memory listing = Listing({
            type_: type_,
            zeroProtocolFee: false,
            seller: msg.sender,
            payoutReceiver: payoutReceiver,
            currencyAddress: currencyAddress,
            openTime: openTime,
            reservePrice: reservePrice,
            buyNowPrice: buyNowPrice,
            startTime: 0,
            duration: auctionDuration,
            recipient: address(0),
            highestBidder: address(0),
            highestBid: 0,
            id: id
        });

        // adjust listing based on listing type
        if (type_ == ListingType.SCHEDULED_AUCTION) {
            listing.startTime = openTime;
            listing.buyNowPrice = 0;
        } else if (type_ == ListingType.RESERVE_AUCTION) {
            listing.buyNowPrice = 0;
        } else if (type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW) {
            // do nothing
        } else if (type_ == ListingType.BUY_NOW) {
            listing.reservePrice = 0;
            listing.duration = 0;
        } else {
            revert InvalidListingType();
        }

        // set listing
        _listings[nftAddress][tokenId] = listing;

        // escrow token, should revert if contract isn't approved
        nftContract.transferFrom(msg.sender, address(this), tokenId);

        // check to ensure it was escrowed
        if (nftContract.ownerOf(tokenId) != address(this)) revert TokenNotTransferred();

        emit ListingConfigured(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to cancel a listing
    /// @dev Requirements
    ///      - only the seller of the listing can delist
    ///      - the listing must be active
    ///      - the auction cannot have been started when delisting
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function delist(address nftAddress, uint256 tokenId) external whenNotPaused nonReentrant {
        // cache data
        IERC721 nftContract = IERC721(nftAddress);
        Listing memory listing = _listings[nftAddress][tokenId];

        // revert if caller is not seller
        // this also catches if the nft is not listing, as the seller is the zero address
        if (msg.sender != listing.seller) revert NotSeller();

        // check if auction has been bid on (this should always pass if listing type is BUY_NOW)
        if (listing.highestBidder != address(0)) revert AuctionStarted();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // transfer token back to seller
        nftContract.transferFrom(address(this), listing.seller, tokenId);

        emit ListingCanceled(msg.sender, nftAddress, tokenId);
    }

    /// @notice Function to bid on a token that has an auction configured
    /// @dev Requirements
    ///      - msg.sender & recipient can't be sanctioned addresses
    ///      - recipient cannot be the zero address
    ///      - a listing must be configured as an auction
    ///      - the block timestamp is past the listing open time
    ///      - the bid can't be too low (under reserve price for first bid or under next bid for subsequent bids)
    ///      - the auction can't have ended
    ///      - the funds sent must match `amount` exactly when bidding
    ///      - the previous bid is sent back
    ///      - if bidding with ERC-20 tokens, no ETH is allowed to be sent
    ///      - if a bid comes within `EXTENSION_TIME`, extend the auction back to `EXTENSION_TIME`
    ///      - the bidder can specify a recipient for the nft they are bidding on, which allows for cross-chain bids to occur
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param recipient The recipient that will receive the NFT if the bid is the winning bid
    /// @param amount The amount to bid
    function bid(address nftAddress, uint256 tokenId, address recipient, uint256 amount)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // check sender & recipient
        _isSanctioned(msg.sender, true);
        if (!_isValidRecipient(recipient)) revert InvalidRecipient();

        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];
        uint256 previousBid = listing.highestBid;
        address previousBidder = listing.highestBidder;

        // check the listing type
        if (listing.type_ == ListingType.NOT_CONFIGURED || listing.type_ == ListingType.BUY_NOW) {
            revert InvalidListingType();
        }

        // cannot bid if prior to listing.openTime
        if (block.timestamp < listing.openTime) revert CannotBidYet();

        // check constraints on first bid versus other bids
        if (previousBidder == address(0)) {
            // first bid cannot bid under reserve price
            if (amount < listing.reservePrice) revert BidTooLow();

            // set start time if reserve auction
            if (
                listing.type_ == ListingType.RESERVE_AUCTION
                    || listing.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW
            ) {
                listing.startTime = block.timestamp;
            }

            // if scheduled auction, make sure that can't bid on a token that has gone past the scheduled duration without bids
            if (listing.type_ == ListingType.SCHEDULED_AUCTION) {
                if (block.timestamp > listing.startTime + listing.duration) revert AuctionEnded();
            }
        } else {
            // subsequent bids
            // cannot bid after auction is ended
            if (block.timestamp > listing.startTime + listing.duration) revert AuctionEnded();

            // ensure amount being bid is greater than minimum next bid
            if (amount < _calcNextBid(listing.highestBid)) revert BidTooLow();
        }

        // update auction, extending duration if needed
        listing.highestBid = amount;
        listing.highestBidder = msg.sender;
        listing.recipient = recipient;
        uint256 timeRemaining = listing.startTime + listing.duration - block.timestamp; // checks for being past auction end time avoid underflow issues here
        if (timeRemaining < EXTENSION_TIME) {
            listing.duration += EXTENSION_TIME - timeRemaining;
        }

        // save new listing items in storage
        _listings[nftAddress][tokenId].highestBid = listing.highestBid;
        _listings[nftAddress][tokenId].highestBidder = listing.highestBidder;
        _listings[nftAddress][tokenId].recipient = listing.recipient;
        if (_listings[nftAddress][tokenId].startTime != listing.startTime) {
            _listings[nftAddress][tokenId].startTime = listing.startTime;
        }
        if (_listings[nftAddress][tokenId].duration != listing.duration) {
            _listings[nftAddress][tokenId].duration = listing.duration;
        }

        // transfer funds as needed for the bid
        if (listing.currencyAddress == address(0)) {
            // ETH
            // escrow msg.value
            if (msg.value != amount) revert UnexpectedMsgValue();
        } else {
            // ERC-20
            // make sure they didn't send any ETH along
            if (msg.value != 0) revert UnexpectedMsgValue();

            // escrow amount from sender (not recipient)
            _safeTransferFromERC20(msg.sender, address(this), listing.currencyAddress, amount);
        }

        // return previous bid, if it's a subsequent bid
        _payout(previousBidder, listing.currencyAddress, previousBid);

        emit AuctionBid(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to settle an auction
    /// @dev Requirements
    ///      - can be called by anyone on the blockchain
    ///      - the listing must be configured as an auction
    ///      - the auction must have been started AND ended
    ///      - royalties are paid out on secondary sales, where the creator of the token is not the seller
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function settleAuction(address nftAddress, uint256 tokenId) external whenNotPaused nonReentrant {
        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check to make sure the listing is the right type
        if (listing.type_ == ListingType.NOT_CONFIGURED || listing.type_ == ListingType.BUY_NOW) {
            revert InvalidListingType();
        }

        // check that auction was bid on
        if (listing.highestBidder == address(0)) revert AuctionNotStarted();

        // ensure auction is ended
        if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // settle up
        _settleUp(
            nftAddress,
            tokenId,
            listing.zeroProtocolFee,
            listing.recipient,
            listing.currencyAddress,
            listing.seller,
            listing.payoutReceiver,
            listing.highestBid
        );

        emit AuctionSettled(msg.sender, nftAddress, tokenId, listing);
    }

    /// @notice Function to buy a token at a fixed price
    /// @dev Requirements
    ///      - msg.sender and recipient cannot be sanctioned
    ///      - recipient cannot be the zero address
    ///      - listing must be configured as a reserve auction with a buy now price or just a buy now
    ///      - if it's an auction + buy now, the auction cannot be started
    ///      - the listing must be open
    ///      - royalties are paid out for secondary sales, where the creator of the token is not the seller
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    /// @param recipient The recipient that will receive the NFT if the bid is the winning bid
    function buyNow(address nftAddress, uint256 tokenId, address recipient)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // check sender & recipient
        _isSanctioned(msg.sender, true);
        if (!_isValidRecipient(recipient)) revert InvalidRecipient();

        // cache data
        Listing memory listing = _listings[nftAddress][tokenId];

        // check the listing type
        if (
            listing.type_ == ListingType.NOT_CONFIGURED || listing.type_ == ListingType.SCHEDULED_AUCTION
                || listing.type_ == ListingType.RESERVE_AUCTION
        ) {
            revert InvalidListingType();
        }

        // cannot buy if an auction is live
        if (listing.highestBidder != address(0)) revert AuctionStarted();

        // cannot buy if prior to listing.openTime
        if (block.timestamp < listing.openTime) revert CannotBuyYet();

        // delete listing & auction
        delete _listings[nftAddress][tokenId];

        // handle funds transfer
        if (listing.currencyAddress == address(0)) {
            // ETH
            // escrow msg.value
            if (msg.value != listing.buyNowPrice) revert UnexpectedMsgValue();
        } else {
            // ERC-20
            // make sure they didn't send any ETH along
            if (msg.value != 0) revert UnexpectedMsgValue();

            // escrow amount from sender (not recipient)
            _safeTransferFromERC20(msg.sender, address(this), listing.currencyAddress, listing.buyNowPrice);
        }

        // settle up
        _settleUp(
            nftAddress,
            tokenId,
            listing.zeroProtocolFee,
            recipient,
            listing.currencyAddress,
            listing.seller,
            listing.payoutReceiver,
            listing.buyNowPrice
        );

        emit BuyNowFulfilled(msg.sender, nftAddress, tokenId, recipient, listing);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// ADMIN FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Function to set a new weth address
    /// @dev Requires owner
    /// @param newWethAddress The weth contract address
    function setWethAddress(address newWethAddress) external onlyOwner {
        address prevWethAddress = weth;
        weth = newWethAddress;

        emit WethUpdated(prevWethAddress, newWethAddress);
    }

    /// @notice Function to set the protocol fee settings
    /// @dev Requires owner
    /// @dev The new protocol fee bps must be out of `BASIS`
    /// @param newProtocolFeeReceiver The new address to receive protocol fees
    /// @param newProtocolFeeBps The new bps for the protocol fee
    function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFeeBps) external onlyOwner {
        if (!_isValidRecipient(newProtocolFeeReceiver)) revert InvalidRecipient();
        if (newProtocolFeeBps > BASIS) revert InvalidProtocolFeeBps();

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
    }

    ///////////////////////////////////////////////////////////////////////////
    /// VIEW FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Function to get a specific listing
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        Listing memory listing = _listings[nftAddress][tokenId];

        return listing;
    }

    /// @notice Function to get the next bid amount for a token
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getNextBid(address nftAddress, uint256 tokenId) external view returns (uint256) {
        Listing memory listing = _listings[nftAddress][tokenId];

        return _calcNextBid(listing.highestBid);
    }

    /// @notice Function to understand if the sale is a primary or secondary sale
    /// @param nftAddress The nft contract address
    /// @param tokenId The nft token id
    function getIfPrimarySale(address nftAddress, uint256 tokenId) external view returns (bool) {
        Listing memory listing = _listings[nftAddress][tokenId];
        return creatorLookup.getCreator(nftAddress, tokenId) == listing.seller;
    }

    /// @notice Function to get the royalty amount that will be paid to the creator
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
            return (recipients, amounts);
        } catch {
            return (new address payable[](0), new uint256[](0));
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// HELPER FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Internal function to check if an nft recipient is valid
    /// @dev Returns false if the recipient is sanctioned or if it is the zero address
    function _isValidRecipient(address recipient) private view returns (bool) {
        if (recipient == address(0)) return false;
        if (_isSanctioned(recipient, false)) return false;
        return true;
    }

    /// @notice Internal function to calculate the next bid price
    /// @param currentBid The current bid
    /// @return nextBid The next bid
    function _calcNextBid(uint256 currentBid) private pure returns (uint256 nextBid) {
        uint256 inc = currentBid * BID_INCREASE_BPS / BASIS;
        if (inc == 0) {
            return currentBid + 1;
        } else {
            return currentBid + inc;
        }
    }

    /// @notice Internal function to abstract payouts when settling a listing
    function _payout(address to, address currencyAddress, uint256 value) private {
        if (to == address(0) || value == 0) return;

        if (currencyAddress == address(0)) {
            _safeTransferETH(to, value, weth);
        } else {
            _safeTransferERC20(to, currencyAddress, value);
        }
    }

    /// @notice Internal function to settle a sale/Auction
    function _settleUp(
        address nftAddress,
        uint256 tokenId,
        bool zeroProtocolFee,
        address recipient,
        address currencyAddress,
        address seller,
        address payoutReceiver,
        uint256 value
    ) private {
        uint256 remainingValue = value;

        // take protocol fee (if not zeroed by contract owner)
        if (!zeroProtocolFee) {
            uint256 protocolFee = value * protocolFeeBps / BASIS;
            remainingValue -= protocolFee;
            _payout(protocolFeeReceiver, currencyAddress, protocolFee);
        }

        // if secondary sale, payout royalties (seller is not the creator)
        address creator = creatorLookup.getCreator(nftAddress, tokenId);
        if (seller != creator && address(royaltyLookup).code.length > 0) {
            // secondary sale
            try royaltyLookup.getRoyalty(nftAddress, tokenId, remainingValue) returns (
                address payable[] memory recipients, uint256[] memory amounts
            ) {
                if (recipients.length == amounts.length) {
                    // payout if array lengths match
                    for (uint256 i = 0; i < recipients.length; ++i) {
                        if (_isSanctioned(recipients[i], false)) continue; // don't pay to sanctioned addresses
                        if (amounts[i] > remainingValue) break;
                        remainingValue -= amounts[i];
                        _payout(recipients[i], currencyAddress, amounts[i]);
                    }
                }
            } catch {
                // do nothing if royalty lookup call fails
                // this causes the coverage test to say a line is missing coverage
            }
        }

        // pay remaining amount to payout receiver (set by the seller)
        _payout(payoutReceiver, currencyAddress, remainingValue);

        // transfer nft to recipient
        IERC721(nftAddress).transferFrom(address(this), recipient, tokenId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {StdInvariant} from "forge-std-1.9.4/StdInvariant.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {ListingType, Listing} from "src/utils/TLAuctionHouseUtils.sol";
import {AuctionHouseHandler} from "test/invariant/handlers/AuctionHouseHandler.sol";

/// @dev Stateful invariants for TLAuctionHouse. IDs refer to docs/invariants.md and docs/trust-model.md.
contract TLAuctionHouseInvariantTest is Test {
    AuctionHouseHandler handler;
    TLAuctionHouse ah;
    address nftAddress;

    function setUp() public {
        handler = new AuctionHouseHandler();
        ah = handler.ah();
        nftAddress = address(handler.nft());

        bytes4[] memory selectors = new bytes4[](20);
        selectors[0] = AuctionHouseHandler.list.selector;
        selectors[1] = AuctionHouseHandler.batchList.selector;
        selectors[2] = AuctionHouseHandler.updateListing.selector;
        selectors[3] = AuctionHouseHandler.updatePayoutReceiver.selector;
        selectors[4] = AuctionHouseHandler.delist.selector;
        selectors[5] = AuctionHouseHandler.bid.selector;
        selectors[6] = AuctionHouseHandler.topUpBid.selector;
        selectors[7] = AuctionHouseHandler.buyNow.selector;
        selectors[8] = AuctionHouseHandler.settleAuction.selector;
        selectors[9] = AuctionHouseHandler.cancelUnsettledAuction.selector;
        selectors[10] = AuctionHouseHandler.claimFunds.selector;
        selectors[11] = AuctionHouseHandler.claimNft.selector;
        selectors[12] = AuctionHouseHandler.warp.selector;
        selectors[13] = AuctionHouseHandler.setProtocolFeeSettings.selector;
        selectors[14] = AuctionHouseHandler.removeProtocolFee.selector;
        selectors[15] = AuctionHouseHandler.setPaused.selector;
        selectors[16] = AuctionHouseHandler.setCurrencyAllowed.selector;
        selectors[17] = AuctionHouseHandler.setRoyaltySchedule.selector;
        selectors[18] = AuctionHouseHandler.setSanctioned.selector;
        selectors[19] = AuctionHouseHandler.transferCollectionOwnership.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev §8 escrow accounting: the house holds exactly the live bids plus every recorded credit, per currency
    function invariant_solvency() public view {
        uint256 numCurrencies = handler.numCurrencies();
        for (uint256 c = 0; c < numCurrencies; ++c) {
            address currency = handler.currencies(c);
            uint256 owed;
            for (uint256 id = 1; id <= handler.NUM_TOKENS(); ++id) {
                Listing memory l = ah.getListing(nftAddress, id);
                if (l.highestBidder != address(0) && l.currencyAddress == currency) owed += l.highestBid;
            }
            uint256 numHolders = handler.numCreditHolders();
            for (uint256 i = 0; i < numHolders; ++i) {
                owed += ah.claimableFunds(handler.creditHolders(i), currency);
            }
            uint256 held = currency == address(0) ? address(ah).balance : IERC20(currency).balanceOf(address(ah));
            assertEq(held, owed, "escrow balance != live bids + claimable credits");
        }
    }

    /// @dev The house holds a token iff it is listed or held for a claim, and never both
    function invariant_nftCustody() public view {
        for (uint256 id = 1; id <= handler.NUM_TOKENS(); ++id) {
            bool listed = ah.getListing(nftAddress, id).type_ != ListingType.NOT_CONFIGURED;
            bool claimable = ah.claimableNft(nftAddress, id) != address(0);
            assertFalse(listed && claimable, "token both listed and claimable");
            assertEq(handler.nft().ownerOf(id) == address(ah), listed || claimable, "custody mismatch");
        }
    }

    /// @dev Stored listings keep the shape `_buildListing` gives them, and bids only ever sit on auctions
    function invariant_listingShape() public view {
        for (uint256 id = 1; id <= handler.NUM_TOKENS(); ++id) {
            Listing memory l = ah.getListing(nftAddress, id);
            if (l.type_ == ListingType.NOT_CONFIGURED) {
                assertEq(l.seller, address(0), "unconfigured listing has a seller");
                assertEq(l.highestBid, 0, "unconfigured listing has a bid");
                continue;
            }

            assertTrue(l.seller != address(0) && l.payoutReceiver != address(0), "listing missing parties");
            assertLe(l.id, handler.ghostMaxListingId(), "listing id from the future");

            bool isAuction = l.type_ == ListingType.SCHEDULED_AUCTION || l.type_ == ListingType.RESERVE_AUCTION
                || l.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW;
            bool isReserve =
                l.type_ == ListingType.RESERVE_AUCTION || l.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW;

            if (l.highestBidder == address(0)) {
                assertEq(l.highestBid, 0, "bid amount without a bidder");
                // I-5 holds only until the first bid, since anti-snipe extensions aren't capped
                assertLe(l.duration, ah.MAX_AUCTION_DURATION(), "I-5: unbid listing over max duration");
                if (isReserve) assertEq(l.startTime, 0, "reserve auction started without a bid");
                if (l.type_ != ListingType.PRIVATE_SALE) assertEq(l.recipient, address(0), "recipient without a bid");
            } else {
                assertTrue(isAuction, "bid on a non-auction listing");
                assertEq(l.recipient, l.highestBidder, "recipient != highest bidder");
                assertGe(l.highestBid, Math.max(l.reservePrice, 1), "high bid below reserve");
                assertGt(l.startTime, 0, "auction with a bid has no start time");
            }

            if (l.type_ == ListingType.SCHEDULED_AUCTION) assertEq(l.startTime, l.openTime, "scheduled start moved");
            if (l.type_ == ListingType.SCHEDULED_AUCTION || l.type_ == ListingType.RESERVE_AUCTION) {
                assertEq(l.buyNowPrice, 0, "auction-only listing has a buy now price");
            }
            if (l.type_ == ListingType.BUY_NOW || l.type_ == ListingType.PRIVATE_SALE) {
                assertEq(l.duration, 0, "fixed price listing has a duration");
                assertEq(l.reservePrice, 0, "fixed price listing has a reserve");
            }
            if (l.type_ == ListingType.PRIVATE_SALE) {
                assertTrue(l.recipient != address(0), "private sale without a recipient");
            }
        }
    }

    /// @dev I-3
    function invariant_protocolFeeBound() public view {
        assertLe(ah.protocolFeeBps(), ah.MAX_PROTOCOL_FEE_BPS(), "I-3: protocol fee above cap");
    }

    /// @dev I-6: a fee waiver on a live listing is only set by the owner and is never cleared in place
    function invariant_zeroProtocolFeeSticky() public view {
        for (uint256 id = 1; id <= handler.NUM_TOKENS(); ++id) {
            Listing memory l = ah.getListing(nftAddress, id);
            if (l.type_ == ListingType.NOT_CONFIGURED) continue;
            assertEq(l.zeroProtocolFee, handler.ghostZeroFee(id), "I-6: fee waiver changed on a live listing");
        }
    }

    /// @dev Per-call properties checked inside the handler (E-1, I-8, I-10, I-11, G-*)
    function invariant_handlerAssertions() public view {
        assertEq(handler.violations(), 0, handler.lastViolation());
    }

    /// @dev A deterministic sequence makes the sale checks mandatory even if a random campaign finds no live sale.
    function test_successfulAuctionAndBuyNowTransitions() public {
        handler.list(0, 2, 0, 0, 0, 0, 0, 0, 1 days);
        assertEq(handler.successes("list"), 1, "reserve auction was not listed");

        handler.bid(0, 1, 1, 1);
        handler.bid(0, 2, 3, 1);
        assertEq(handler.successes("bid"), 2, "bids did not land");

        handler.warp(8 days);
        handler.settleAuction(0, 0);
        assertEq(handler.successes("settleAuction"), 1, "auction was not settled");

        handler.list(1, 4, 0, 0, 0, 0, 0, 1 ether, 0);
        assertEq(handler.successes("list"), 2, "fixed-price sale was not listed");
        handler.buyNow(1, 3, 3);
        assertEq(handler.successes("buyNow"), 1, "fixed-price sale was not bought");

        invariant_solvency();
        invariant_nftCustody();
        invariant_listingShape();
        invariant_handlerAssertions();
    }
}

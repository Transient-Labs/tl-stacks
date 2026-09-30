// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {RoyaltyLookup} from "src/helpers/RoyaltyLookup.sol";
import {SanctionsCompliance} from "src/lib/SanctionsCompliance.sol";
import {CurrencyAllowlist} from "src/lib/CurrencyAllowlist.sol";
import {ListingType, Listing, ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockRoyaltyLookup} from "test/utils/MockRoyaltyLookup.sol";
import {MockSanctionsOracle} from "test/utils/MockSanctionsOracle.sol";

/// @dev Pins behavior documented in docs/trust-model.md and docs/invariants.md, including the properties marked
///      "On-chain: No". If one of these fails, the documented behavior changed and the docs need to change with it.
contract TLAuctionHouseEdgeTest is Test {
    uint256 constant BASIS = 10_000;
    uint256 constant TOKEN = 1; // held by `seller`, so sales are secondary unless the collection owner changes

    TLAuctionHouse ah;
    ERC721TL nft;
    MockERC20 coin;
    MockSanctionsOracle oracle;
    MockRoyaltyLookup royaltyLookup;

    address creator = makeAddr("creator");
    address seller = makeAddr("seller");
    address payout = makeAddr("payout");
    address feeReceiver = makeAddr("feeReceiver");
    address bidder1 = makeAddr("bidder1");
    address bidder2 = makeAddr("bidder2");
    address royalty0 = makeAddr("royalty0");
    address royalty1 = makeAddr("royalty1");

    function setUp() public {
        oracle = new MockSanctionsOracle();
        ah = new TLAuctionHouse(address(this), address(oracle));
        royaltyLookup = new MockRoyaltyLookup();
        ah.setCreatorLookup(address(new CreatorLookup()));
        ah.setRoyaltyLookup(address(royaltyLookup));
        ah.setProtocolFeeSettings(feeReceiver, 100);
        _setRoyalty(royaltyLookup, royalty0, 1_000);

        coin = new MockERC20(address(this));
        ah.setCurrencyAllowed(address(coin), true);

        address[] memory empty = new address[](0);
        nft = new ERC721TL(false);
        nft.initialize("Edge", "EDGE", creator, 1_000, creator, empty, false, address(0), 0, address(0));
        vm.prank(creator);
        nft.mint(seller, "https://arweave.net/1");
        vm.prank(seller);
        nft.setApprovalForAll(address(ah), true);

        vm.deal(bidder1, 1_000 ether);
        vm.deal(bidder2, 1_000 ether);
    }

    /////////////////////////////////////////////////////////////////////
    // TIMING
    /////////////////////////////////////////////////////////////////////

    /// @dev I-5 (not enforced on-chain): late bids extend `duration` past MAX_AUCTION_DURATION, which only caps the
    ///      configured duration
    function test_I5_antiSnipeExtendsPastMaxDuration() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, ah.MAX_AUCTION_DURATION());
        _bid(bidder1, 1 ether, lid);

        for (uint256 i = 0; i < 10; ++i) {
            Listing memory l = ah.getListing(address(nft), TOKEN);
            vm.warp(l.startTime + l.duration); // last second of the auction
            _bid(i % 2 == 0 ? bidder2 : bidder1, ah.getNextBid(address(nft), TOKEN), lid);
        }

        Listing memory end = ah.getListing(address(nft), TOKEN);
        assertEq(end.duration, ah.MAX_AUCTION_DURATION() + 10 * ah.EXTENSION_TIME(), "each snipe adds the extension");
        assertGt(end.duration, ah.MAX_AUCTION_DURATION());

        vm.warp(end.startTime + end.duration + 1);
        ah.settleAuction(address(nft), TOKEN);
        assertEq(nft.ownerOf(TOKEN), end.highestBidder);
    }

    /// @dev A reserve auction configured with zero duration still runs for EXTENSION_TIME after the first bid
    function test_reserveAuction_zeroDurationRunsForExtension() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 0);
        _bid(bidder1, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        assertEq(l.startTime + l.duration, block.timestamp + ah.EXTENSION_TIME());
    }

    /// @dev G-12: a zero reserve still requires a non-zero first bid
    function test_G12_zeroReserveNeedsNonZeroBid() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), TOKEN, address(0), 0, lid);
        _bid(bidder1, 1, lid);
        assertEq(ah.getListing(address(nft), TOKEN).highestBid, 1);
    }

    /////////////////////////////////////////////////////////////////////
    // PAUSE
    /////////////////////////////////////////////////////////////////////

    /// @dev I-9 (not enforced on-chain): cancel credits funds and an nft while paused, and both claims stay open
    function test_I9_cancelAndClaimsWorkWhilePaused() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);

        ah.pause(true);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ah.settleAuction(address(nft), TOKEN);

        vm.prank(bidder1);
        ah.cancelUnsettledAuction(address(nft), TOKEN);
        assertEq(ah.claimableFunds(bidder1, address(0)), 1 ether, "bid not credited while paused");
        assertEq(ah.claimableNft(address(nft), TOKEN), seller, "nft not credited while paused");

        uint256 balance = bidder1.balance;
        vm.prank(bidder1);
        ah.claimFunds(address(0), bidder1);
        assertEq(bidder1.balance, balance + 1 ether);

        vm.prank(seller);
        ah.claimNft(address(nft), TOKEN, seller);
        assertEq(nft.ownerOf(TOKEN), seller);
        assertEq(address(ah).balance, 0);
    }

    /////////////////////////////////////////////////////////////////////
    // VALUES READ AT SETTLEMENT
    /////////////////////////////////////////////////////////////////////

    /// @dev I-13: the protocol fee rate is read at settlement, not at listing or bid time
    function test_I13_protocolFeeReadAtSettlement() public {
        _setRoyalty(royaltyLookup, royalty0, 0);
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 10 ether, lid);

        ah.setProtocolFeeSettings(feeReceiver, ah.MAX_PROTOCOL_FEE_BPS());
        _settle();
        assertEq(feeReceiver.balance, 10 ether * ah.MAX_PROTOCOL_FEE_BPS() / BASIS, "fee not from settlement rate");
        assertEq(payout.balance, 10 ether - feeReceiver.balance);
    }

    /// @dev X-1 (not enforced on-chain): primary vs secondary is decided at settlement from the collection's current
    ///      owner, so moving collection ownership after the bid moves the royalties
    function test_X1_collectionOwnerChangeFlipsPrimary() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        assertFalse(ah.getIfPrimarySale(address(nft), TOKEN), "listed as secondary");
        _bid(bidder1, 10 ether, lid);

        vm.prank(creator);
        nft.transferOwnership(seller);
        assertTrue(ah.getIfPrimarySale(address(nft), TOKEN), "now primary");

        _settle();
        assertEq(royalty0.balance, 0, "royalties paid on what became a primary sale");
        assertEq(payout.balance, 10 ether - feeReceiver.balance);
    }

    /// @dev X-1: the reverse, a primary sale turns secondary if the lookup is removed before settlement, since an
    ///      unset lookup counts as secondary
    function test_X1_creatorLookupRemovedMakesSecondary() public {
        vm.prank(creator);
        nft.transferOwnership(seller);
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        assertTrue(ah.getIfPrimarySale(address(nft), TOKEN));
        _bid(bidder1, 10 ether, lid);

        ah.setCreatorLookup(address(0));
        _settle();
        assertEq(royalty0.balance, 1 ether, "royalty skipped after lookup removed");
    }

    /// @dev X-2 (not enforced on-chain): swapping the royalty lookup between bid and settlement changes who is paid;
    ///      the 10% cap still applies to the new schedule
    function test_X2_royaltyLookupSwapBetweenBidAndSettle() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 10 ether, lid);
        (address payable[] memory quoted,) = ah.getRoyalty(address(nft), TOKEN, 10 ether);
        assertEq(quoted[0], royalty0);

        MockRoyaltyLookup other = new MockRoyaltyLookup();
        _setRoyalty(other, royalty1, 5_000); // 50%, capped to 10%
        ah.setRoyaltyLookup(address(other));

        _settle();
        assertEq(royalty0.balance, 0, "old schedule paid");
        assertEq(royalty1.balance, 1 ether, "new schedule not paid at the cap");
    }

    /// @dev X-3 (not enforced on-chain): once an engine is set, RoyaltyLookup returns the engine's schedule and
    ///      ignores the token's ERC-2981 royalty; an engine without code means no royalties at all
    function test_X3_engineOverridesERC2981() public {
        RoyaltyLookup rl = new RoyaltyLookup(address(this));
        ah.setRoyaltyLookup(address(rl));
        (, uint256[] memory amounts2981) = ah.getRoyalty(address(nft), TOKEN, 10 ether);
        assertEq(amounts2981[0], 1 ether, "ERC-2981 default royalty");

        MockRoyaltyLookup engine = new MockRoyaltyLookup();
        _setRoyalty(engine, royalty1, 200);
        rl.setRoyaltyEngine(address(engine));

        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 10 ether, lid);
        _settle();
        assertEq(royalty1.balance, 0.2 ether, "engine schedule not paid");
        assertEq(creator.balance, 0, "ERC-2981 receiver paid despite engine");
    }

    /// @dev X-3: an engine address with no code yields no royalties, so the seller keeps the royalty share
    function test_X3_codelessEngineMeansNoRoyalties() public {
        RoyaltyLookup rl = new RoyaltyLookup(address(this));
        rl.setRoyaltyEngine(makeAddr("not a contract"));
        ah.setRoyaltyLookup(address(rl));

        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 10 ether, lid);
        _settle();
        assertEq(creator.balance, 0);
        assertEq(payout.balance, 10 ether - feeReceiver.balance);
    }

    /////////////////////////////////////////////////////////////////////
    // ALLOWLIST, SANCTIONS, SELF-BIDS, ZERO PRICE
    /////////////////////////////////////////////////////////////////////

    /// @dev Removing a currency blocks new listings only; a live listing in it can still be bid on and settled
    function test_removedCurrency_liveListingStillSettles() public {
        vm.prank(seller);
        ah.list(_cfg(ListingType.RESERVE_AUCTION, address(coin), 0, 1 days, 0));
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        ah.setCurrencyAllowed(address(coin), false);

        coin.transfer(bidder1, 5 ether);
        vm.startPrank(bidder1);
        coin.approve(address(ah), type(uint256).max);
        ah.bid(address(nft), TOKEN, address(coin), 5 ether, lid);
        vm.stopPrank();

        _settle();
        assertEq(nft.ownerOf(TOKEN), bidder1);

        vm.prank(bidder1);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(bidder1);
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        ah.list(_cfg(ListingType.RESERVE_AUCTION, address(coin), 0, 1 days, 0));
    }

    /// @dev Trust model §10: a seller sanctioned after a bid blocks settlement; the unwind is cancel after the grace
    ///      period, and the seller's nft stays frozen until the flag clears
    function test_sanctionedSellerAfterBid_unwindAndFrozenClaim() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 1 ether, lid);
        oracle.setSanctioned(seller, true);

        Listing memory l = ah.getListing(address(nft), TOKEN);
        vm.warp(l.startTime + l.duration + 1);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.settleAuction(address(nft), TOKEN);

        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);
        vm.prank(bidder1);
        ah.cancelUnsettledAuction(address(nft), TOKEN);

        vm.prank(seller);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.claimNft(address(nft), TOKEN, seller);

        oracle.setSanctioned(seller, false);
        vm.prank(seller);
        ah.claimNft(address(nft), TOKEN, seller);
        assertEq(nft.ownerOf(TOKEN), seller);

        vm.prank(bidder1);
        ah.claimFunds(address(0), bidder1);
        assertEq(bidder1.balance, 1_000 ether);
    }

    /// @dev The high bidder can outbid themselves; the earlier bid comes straight back
    function test_selfOutbidRefundsEarlierBid() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 1 ether, lid);
        _bid(bidder1, 2 ether, lid);
        assertEq(bidder1.balance, 1_000 ether - 2 ether);
        assertEq(address(ah).balance, 2 ether);
        assertEq(ah.claimableFunds(bidder1, address(0)), 0);
    }

    /// @dev A zero-price buy now delivers the nft, pays nobody, and rejects any ETH sent with it
    function test_buyNow_zeroPrice() public {
        uint256 lid = _listEth(ListingType.BUY_NOW, 0, 0);

        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.buyNow{value: 1}(address(nft), TOKEN, bidder1, address(0), 0, lid);

        vm.prank(bidder1);
        ah.buyNow(address(nft), TOKEN, bidder1, address(0), 0, lid);
        assertEq(nft.ownerOf(TOKEN), bidder1);
        assertEq(payout.balance + feeReceiver.balance + royalty0.balance, 0);
    }

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _cfg(ListingType type_, address currency, uint256 reservePrice, uint256 duration, uint256 buyNowPrice)
        internal
        view
        returns (ListingConfig memory)
    {
        return
            ListingConfig(
                address(nft), TOKEN, type_, payout, currency, 0, reservePrice, duration, buyNowPrice, address(0)
            );
    }

    function _listEth(ListingType type_, uint256 reservePrice, uint256 duration) internal returns (uint256) {
        vm.prank(seller);
        ah.list(_cfg(type_, address(0), reservePrice, duration, 0));
        return ah.getListing(address(nft), TOKEN).id;
    }

    function _bid(address bidder, uint256 amount, uint256 lid) internal {
        vm.prank(bidder);
        ah.bid{value: amount}(address(nft), TOKEN, address(0), amount, lid);
    }

    function _settle() internal {
        Listing memory l = ah.getListing(address(nft), TOKEN);
        vm.warp(l.startTime + l.duration + 1);
        ah.settleAuction(address(nft), TOKEN);
    }

    function _setRoyalty(MockRoyaltyLookup lookup, address recipient, uint256 bps) internal {
        address payable[] memory r = new address payable[](1);
        uint256[] memory a = new uint256[](1);
        (r[0], a[0]) = (payable(recipient), bps);
        lookup.setSchedule(r, a, true);
    }
}

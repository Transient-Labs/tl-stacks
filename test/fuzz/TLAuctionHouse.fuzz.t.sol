// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {ListingType, Listing, ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockRoyaltyLookup} from "test/utils/MockRoyaltyLookup.sol";
import {RevertingReceiver} from "test/utils/Receiver.sol";

/// @dev Stateless fuzz tests for TLAuctionHouse payouts and exact boundaries. IDs refer to docs/invariants.md.
contract TLAuctionHouseFuzzTest is Test {
    uint256 constant BASIS = 10_000;
    uint256 constant PRIMARY_TOKEN = 1; // held by the collection owner
    uint256 constant SECONDARY_TOKEN = 2; // held by someone else

    TLAuctionHouse ah;
    ERC721TL nft;
    MockERC20 coin;
    MockRoyaltyLookup royaltyLookup;

    address creator = makeAddr("creator");
    address seller = makeAddr("seller");
    address payout = makeAddr("payout");
    address feeReceiver = makeAddr("feeReceiver");
    address buyer = makeAddr("buyer");
    address bidder1 = makeAddr("bidder1");
    address bidder2 = makeAddr("bidder2");

    struct Partition {
        uint256 value;
        uint256 bps;
        bool zeroFee;
        bool primary;
        bool erc20;
        bool viaAuction;
        uint256 n;
        bool mismatch;
        uint256 mask;
        uint256[15] amounts;
    }

    function setUp() public {
        ah = new TLAuctionHouse(address(this), address(0));
        royaltyLookup = new MockRoyaltyLookup();
        ah.setCreatorLookup(address(new CreatorLookup()));
        ah.setRoyaltyLookup(address(royaltyLookup));
        ah.setProtocolFeeSettings(feeReceiver, 0);

        coin = new MockERC20(address(this));
        ah.setCurrencyAllowed(address(coin), true);

        address[] memory empty = new address[](0);
        nft = new ERC721TL(false);
        nft.initialize("Fuzz", "FUZZ", creator, 1_000, creator, empty, false, address(0), 0, address(0));
        vm.startPrank(creator);
        nft.mint(creator, "https://arweave.net/1");
        nft.mint(seller, "https://arweave.net/2");
        nft.setApprovalForAll(address(ah), true);
        vm.stopPrank();
        vm.prank(seller);
        nft.setApprovalForAll(address(ah), true);
    }

    /////////////////////////////////////////////////////////////////////
    // E-1 PAYOUT PARTITION
    /////////////////////////////////////////////////////////////////////

    /// @dev E-1, I-13, I-14 through `buyNow`
    function testFuzz_E1_payoutPartition_buyNow(
        uint256 value,
        uint256 bps,
        bool zeroFee,
        bool primary,
        bool erc20,
        uint256 n,
        bool mismatch,
        uint256 mask,
        uint256[15] memory amounts
    ) public {
        _runPartition(Partition(value, bps, zeroFee, primary, erc20, false, n, mismatch, mask, amounts));
    }

    /// @dev E-1, I-13, I-14 through `settleAuction`
    function testFuzz_E1_payoutPartition_settleAuction(
        uint256 value,
        uint256 bps,
        bool zeroFee,
        bool primary,
        bool erc20,
        uint256 n,
        bool mismatch,
        uint256 mask,
        uint256[15] memory amounts
    ) public {
        _runPartition(Partition(value, bps, zeroFee, primary, erc20, true, n, mismatch, mask, amounts));
    }

    // partition scratch state, kept in storage to stay under the stack limit
    address payable[] internal _recipients;
    uint256[] internal _quotes;
    uint256[] internal _before;

    function _runPartition(Partition memory p) internal {
        p.value = bound(p.value, 1, 1e30);
        p.bps = bound(p.bps, 0, ah.MAX_PROTOCOL_FEE_BPS());
        p.n = bound(p.n, 0, 15);
        ah.setProtocolFeeSettings(feeReceiver, p.bps);
        address currency = p.erc20 ? address(coin) : address(0);

        // royalty schedule: fresh recipients, some replaced by the zero address or the escrow itself, and amounts
        // that are either small or completely arbitrary (up to uint256 max)
        for (uint256 i = 0; i < p.n; ++i) {
            address payable r = payable(address(uint160(0xA0000 + i)));
            if ((p.mask >> i) & 1 == 1) r = i % 2 == 0 ? payable(address(0)) : payable(address(ah));
            _recipients.push(r);
            _quotes.push((p.mask >> (i + 16)) & 1 == 1 ? p.amounts[i] : p.amounts[i] % (p.value / 5 + 1));
            _before.push(_balance(r, currency));
        }
        if (p.mismatch) _quotes.push(1);
        royaltyLookup.setSchedule(_recipients, _quotes, false);

        uint256 tokenId = p.primary ? PRIMARY_TOKEN : SECONDARY_TOKEN;
        uint256 feeBefore = _balance(feeReceiver, currency);
        uint256 payoutBefore = _balance(payout, currency);
        _sell(p, tokenId, currency);

        // protocol fee is exact, from the rate at settlement
        uint256 feePaid = _balance(feeReceiver, currency) - feeBefore;
        assertEq(feePaid, p.zeroFee ? 0 : p.value * p.bps / BASIS, "protocol fee");

        uint256 royaltiesPaid = _assertRoyalties(p, currency);

        // the seller's receiver gets the rest, the escrow is left empty, and nothing was credited
        assertEq(_balance(payout, currency) - payoutBefore, p.value - feePaid - royaltiesPaid, "payout remainder");
        assertEq(_balance(address(ah), currency), 0, "escrow not emptied");
        assertEq(ah.claimableFunds(payout, currency), 0);
        assertEq(ah.claimableFunds(feeReceiver, currency), 0);
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function _sell(Partition memory p, uint256 tokenId, address currency) internal {
        uint256 lid = _list(
            tokenId,
            p.viaAuction ? ListingType.RESERVE_AUCTION : ListingType.BUY_NOW,
            currency,
            0,
            p.viaAuction ? p.value : 0,
            1 days,
            p.viaAuction ? 0 : p.value
        );
        if (p.zeroFee) ah.removeProtocolFee(address(nft), tokenId);

        _fund(buyer, currency, p.value);
        if (p.viaAuction) {
            vm.prank(buyer);
            ah.bid{value: p.erc20 ? 0 : p.value}(address(nft), tokenId, currency, p.value, lid);
            vm.warp(block.timestamp + 1 days + 1);
            ah.settleAuction(address(nft), tokenId);
        } else {
            vm.prank(buyer);
            ah.buyNow{value: p.erc20 ? 0 : p.value}(address(nft), tokenId, buyer, currency, p.value, lid);
        }
    }

    /// @dev Royalties are paid in order to the first 10 entries only, skip the zero address and the escrow, never
    ///      exceed an entry's quote, and total min(10% of value, sum of payable quotes)
    function _assertRoyalties(Partition memory p, address currency) internal view returns (uint256 royaltiesPaid) {
        uint256 sumValidQuotes;
        for (uint256 i = 0; i < p.n; ++i) {
            bool skipped = _recipients[i] == address(0) || _recipients[i] == address(ah);
            uint256 got = skipped ? 0 : _balance(_recipients[i], currency) - _before[i];
            if (i >= ah.MAX_ROYALTY_RECIPIENTS() || skipped || p.mismatch || p.primary) {
                assertEq(got, 0, "royalty paid to an excluded entry");
            } else {
                assertLe(got, _quotes[i], "royalty above quote");
                sumValidQuotes = _saturatingAdd(sumValidQuotes, _quotes[i]);
            }
            royaltiesPaid += got;
        }
        uint256 budget = p.value * ah.MAX_ROYALTY_BPS() / BASIS;
        assertEq(royaltiesPaid, p.mismatch || p.primary ? 0 : Math.min(budget, sumValidQuotes), "royalty total");
    }

    /// @dev I-14: only the first MAX_ROYALTY_RECIPIENTS entries are paid, even when the 10% budget isn't used up
    function testFuzz_royaltyRecipientLimit(uint256 value, uint256 n) public {
        value = bound(value, 1 ether, 1e30);
        n = bound(n, ah.MAX_ROYALTY_RECIPIENTS() + 1, 30);
        address payable[] memory recipients = new address payable[](n);
        uint256[] memory quotes = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            recipients[i] = payable(address(uint160(0xB0000 + i)));
            quotes[i] = value / 1_000; // 0.1% each, so the budget never binds
        }
        royaltyLookup.setSchedule(recipients, quotes, false);

        uint256 lid = _list(SECONDARY_TOKEN, ListingType.BUY_NOW, address(0), 0, 0, 0, value);
        _fund(buyer, address(0), value);
        vm.prank(buyer);
        ah.buyNow{value: value}(address(nft), SECONDARY_TOKEN, buyer, address(0), value, lid);

        for (uint256 i = 0; i < n; ++i) {
            assertEq(recipients[i].balance, i < ah.MAX_ROYALTY_RECIPIENTS() ? value / 1_000 : 0, "recipient limit");
        }
    }

    /////////////////////////////////////////////////////////////////////
    // BID STEP
    /////////////////////////////////////////////////////////////////////

    /// @dev G-15: the next bid is exactly the 5% step rounded up, and one below it is rejected
    function testFuzz_G15_nextBidStep(uint256 firstBid) public {
        firstBid = bound(firstBid, 1, type(uint256).max / 3); // first bid + outbid must fit in the token supply
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(coin), 0, 0, 1 days, 0);

        _fund(bidder1, address(coin), firstBid);
        vm.prank(bidder1);
        ah.bid(address(nft), SECONDARY_TOKEN, address(coin), firstBid, lid);

        uint256 next = ah.getNextBid(address(nft), SECONDARY_TOKEN);
        assertEq(next - firstBid, Math.mulDiv(firstBid, 500, BASIS, Math.Rounding.Ceil), "step");
        assertGt(next, firstBid, "next bid not higher");

        _fund(bidder2, address(coin), next);
        vm.prank(bidder2);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), SECONDARY_TOKEN, address(coin), next - 1, lid);

        vm.prank(bidder2);
        ah.bid(address(nft), SECONDARY_TOKEN, address(coin), next, lid);
        assertEq(coin.balanceOf(bidder1), firstBid, "outbid bidder not refunded");
        assertEq(coin.balanceOf(address(ah)), next, "escrow != high bid");
    }

    /// @dev `getNextBid` before any bid is the reserve, or 1 since bids can't be zero
    function testFuzz_getNextBid_beforeFirstBid(uint256 reservePrice) public {
        reservePrice = bound(reservePrice, 0, type(uint128).max);
        _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(0), 0, reservePrice, 1 days, 0);
        assertEq(ah.getNextBid(address(nft), SECONDARY_TOKEN), Math.max(reservePrice, 1));
    }

    /////////////////////////////////////////////////////////////////////
    // TIME BOUNDARIES
    /////////////////////////////////////////////////////////////////////

    /// @dev G-14, G-19, G-22: at the stored end a bid or top up still lands, settlement does not; one second later
    ///      it is the reverse
    function testFuzz_endBoundary_bidTopUpSettle(uint256 duration) public {
        duration = bound(duration, 0, 30 days);
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(0), 0, 0, duration, 0);
        _bidEth(bidder1, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
        uint256 end = l.startTime + l.duration;
        assertEq(l.duration, Math.max(duration, ah.EXTENSION_TIME()), "first bid extension");

        // exactly at the end: a new bid lands and pushes the end out by the full extension
        vm.warp(end);
        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), SECONDARY_TOKEN);
        _bidEth(bidder2, 2 ether, lid);
        l = ah.getListing(address(nft), SECONDARY_TOKEN);
        end = l.startTime + l.duration;
        assertEq(end, block.timestamp + ah.EXTENSION_TIME(), "bid at end not extended");

        // exactly at the new end: a top up lands without moving the end
        vm.warp(end);
        vm.deal(bidder2, 1);
        vm.prank(bidder2);
        ah.topUpBid{value: 1}(address(nft), SECONDARY_TOKEN, 1, lid);
        l = ah.getListing(address(nft), SECONDARY_TOKEN);
        assertEq(l.startTime + l.duration, end, "I-10: top up moved the end");
        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), SECONDARY_TOKEN);

        // one second later: bids and top ups are closed and settlement opens
        vm.warp(end + 1);
        vm.deal(bidder1, 10 ether);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.bid{value: 10 ether}(address(nft), SECONDARY_TOKEN, address(0), 10 ether, lid);
        vm.deal(bidder2, 1);
        vm.prank(bidder2);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.topUpBid{value: 1}(address(nft), SECONDARY_TOKEN, 1, lid);
        ah.settleAuction(address(nft), SECONDARY_TOKEN);
        assertEq(nft.ownerOf(SECONDARY_TOKEN), bidder2);
    }

    /// @dev G-28: cancel opens one second after end + grace period, and not before
    function testFuzz_G28_cancelBoundary(uint256 duration, bool bySeller) public {
        duration = bound(duration, 0, 30 days);
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(0), 0, 0, duration, 0);
        _bidEth(bidder1, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
        uint256 cancelOpens = l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1;
        address caller = bySeller ? seller : bidder1;

        vm.warp(cancelOpens - 1);
        vm.prank(caller);
        vm.expectRevert(TLAuctionHouse.SettlementGracePeriodNotOver.selector);
        ah.cancelUnsettledAuction(address(nft), SECONDARY_TOKEN);

        vm.warp(cancelOpens);
        vm.prank(caller);
        ah.cancelUnsettledAuction(address(nft), SECONDARY_TOKEN);
        assertEq(ah.claimableFunds(bidder1, address(0)), 1 ether);
        assertEq(ah.claimableNft(address(nft), SECONDARY_TOKEN), seller);
        assertEq(address(ah).balance, 1 ether);
    }

    /// @dev G-11, G-35: bids and buys open exactly at the stored open time
    function testFuzz_openTimeBoundary(uint256 delay, bool buy) public {
        delay = bound(delay, 1, 365 days);
        uint256 openTime = block.timestamp + delay;
        uint256 lid =
            _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION_PLUS_BUY_NOW, address(0), openTime, 0, 1 days, 5 ether);
        vm.deal(buyer, 5 ether);

        vm.warp(openTime - 1);
        vm.startPrank(buyer);
        if (buy) {
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: 5 ether}(address(nft), SECONDARY_TOKEN, buyer, address(0), 5 ether, lid);
        } else {
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: 1 ether}(address(nft), SECONDARY_TOKEN, address(0), 1 ether, lid);
        }

        vm.warp(openTime);
        if (buy) {
            ah.buyNow{value: 5 ether}(address(nft), SECONDARY_TOKEN, buyer, address(0), 5 ether, lid);
            assertEq(nft.ownerOf(SECONDARY_TOKEN), buyer);
        } else {
            ah.bid{value: 1 ether}(address(nft), SECONDARY_TOKEN, address(0), 1 ether, lid);
            assertEq(ah.getListing(address(nft), SECONDARY_TOKEN).startTime, openTime);
        }
        vm.stopPrank();
    }

    /// @dev G-13: a scheduled auction with no bids accepts a first bid at its end and not after
    function testFuzz_G13_scheduledAuctionFirstBid(uint256 delay, uint256 duration, bool late) public {
        delay = bound(delay, 0, 30 days);
        duration = bound(duration, 0, 30 days);
        uint256 openTime = block.timestamp + delay;
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.SCHEDULED_AUCTION, address(0), openTime, 0, duration, 0);

        vm.warp(openTime + duration + (late ? 1 : 0));
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        if (late) vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.bid{value: 1 ether}(address(nft), SECONDARY_TOKEN, address(0), 1 ether, lid);
        if (!late) {
            Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
            assertEq(l.startTime, openTime, "scheduled start moved");
            assertEq(l.startTime + l.duration, block.timestamp + ah.EXTENSION_TIME(), "last second bid not extended");
        }
    }

    /// @dev Anti-snipe: after every bid the end is max(previous end, now + EXTENSION_TIME)
    function testFuzz_antiSnipeExtension(uint256 duration, uint256 numBids, uint256 seed) public {
        duration = bound(duration, 0, 30 days);
        numBids = bound(numBids, 1, 25);
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(0), 0, 0, duration, 0);
        _bidEth(bidder1, 1 ether, lid);

        for (uint256 i = 0; i < numBids; ++i) {
            Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
            uint256 prevEnd = l.startTime + l.duration;
            seed = uint256(keccak256(abi.encode(seed, i)));
            vm.warp(block.timestamp + seed % (prevEnd - block.timestamp + 1));

            address next = l.highestBidder == bidder1 ? bidder2 : bidder1;
            _bidEth(next, ah.getNextBid(address(nft), SECONDARY_TOKEN), lid);

            l = ah.getListing(address(nft), SECONDARY_TOKEN);
            assertEq(l.startTime + l.duration, Math.max(prevEnd, block.timestamp + ah.EXTENSION_TIME()), "end");
        }
    }

    /////////////////////////////////////////////////////////////////////
    // LISTING CONSTRUCTION
    /////////////////////////////////////////////////////////////////////

    /// @dev `_buildListing` zeroes the fields that don't apply to a type, clamps the open time, caps the duration
    ///      (G-43), and hands out a fresh id
    function testFuzz_buildListing_normalization(
        uint256 typeSeed,
        uint256 openTime,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice,
        address recipient
    ) public {
        vm.warp(1_000_000);
        ListingType type_ = ListingType(bound(typeSeed, 0, 5));
        openTime = bound(openTime, 0, 2_000_000);
        duration = bound(duration, 0, 60 days);
        vm.assume(recipient != address(0));
        ListingConfig memory cfg = ListingConfig(
            address(nft),
            SECONDARY_TOKEN,
            type_,
            payout,
            address(0),
            openTime,
            reservePrice,
            duration,
            buyNowPrice,
            recipient
        );

        bool fixedPrice = type_ == ListingType.BUY_NOW || type_ == ListingType.PRIVATE_SALE;
        bool tooLong = !fixedPrice && duration > ah.MAX_AUCTION_DURATION();
        bool badBuyNow = type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW && buyNowPrice <= reservePrice;
        if (type_ == ListingType.NOT_CONFIGURED) {
            vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        } else if (badBuyNow) {
            vm.expectRevert(TLAuctionHouse.InvalidBuyNowPrice.selector);
        } else if (tooLong) {
            vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        }
        vm.prank(seller);
        ah.list(cfg);
        if (type_ == ListingType.NOT_CONFIGURED || badBuyNow || tooLong) return;

        Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
        uint256 expectedOpen = Math.max(openTime, block.timestamp);
        assertEq(uint8(l.type_), uint8(type_));
        assertEq(l.id, 1);
        assertEq(l.seller, seller);
        assertEq(l.openTime, expectedOpen, "open time not clamped");
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.startTime, type_ == ListingType.SCHEDULED_AUCTION ? expectedOpen : 0, "start time");
        assertEq(l.duration, fixedPrice ? 0 : duration, "duration");
        assertEq(l.reservePrice, fixedPrice ? 0 : reservePrice, "reserve");
        bool auctionOnly = type_ == ListingType.SCHEDULED_AUCTION || type_ == ListingType.RESERVE_AUCTION;
        assertEq(l.buyNowPrice, auctionOnly ? 0 : buyNowPrice, "buy now price");
        assertEq(l.recipient, type_ == ListingType.PRIVATE_SALE ? recipient : address(0), "recipient");
    }

    /// @dev I-6 + ids: `updateListing` issues a new id and keeps an owner fee waiver; `updatePayoutReceiver` keeps
    ///      the id
    function testFuzz_updateListing_keepsWaiverAndBumpsId(
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice,
        bool waive,
        address newPayoutReceiver
    ) public {
        duration = bound(duration, 0, 30 days);
        reservePrice = bound(reservePrice, 0, type(uint256).max - 1);
        buyNowPrice = bound(buyNowPrice, reservePrice + 1, type(uint256).max);
        vm.assume(newPayoutReceiver != address(0));
        uint256 lid =
            _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION_PLUS_BUY_NOW, address(0), 0, 1 ether, 1 days, 2 ether);
        if (waive) ah.removeProtocolFee(address(nft), SECONDARY_TOKEN);

        vm.prank(seller);
        ah.updateListing(
            ListingConfig(
                address(nft),
                SECONDARY_TOKEN,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                payout,
                address(0),
                0,
                reservePrice,
                duration,
                buyNowPrice,
                address(0)
            )
        );
        Listing memory l = ah.getListing(address(nft), SECONDARY_TOKEN);
        assertGt(l.id, lid, "update did not bump the id");
        assertEq(l.zeroProtocolFee, waive, "I-6: waiver not kept");
        assertEq(l.reservePrice, reservePrice);
        assertEq(l.buyNowPrice, buyNowPrice);
        assertEq(l.duration, duration);

        vm.prank(seller);
        ah.updatePayoutReceiver(address(nft), SECONDARY_TOKEN, newPayoutReceiver);
        Listing memory after_ = ah.getListing(address(nft), SECONDARY_TOKEN);
        assertEq(after_.id, l.id, "payout receiver change bumped the id");
        assertEq(after_.payoutReceiver, newPayoutReceiver);
    }

    /////////////////////////////////////////////////////////////////////
    // REFUNDS
    /////////////////////////////////////////////////////////////////////

    /// @dev Across any sequence of outbids, every bidder ends with exactly what they didn't win back (sent or
    ///      credited), and the escrow holds only the high bid plus credits
    function testFuzz_multiBidderRefunds(uint256 seed, uint256 numBids) public {
        numBids = bound(numBids, 2, 20);
        address[4] memory bidders = [bidder1, bidder2, buyer, address(new RevertingReceiver())];
        for (uint256 i = 0; i < 4; ++i) {
            vm.deal(bidders[i], 1_000 ether);
        }
        uint256 lid = _list(SECONDARY_TOKEN, ListingType.RESERVE_AUCTION, address(0), 0, 0, 1 days, 0);

        uint256 winner;
        uint256 highBid;
        for (uint256 i = 0; i < numBids; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 who = seed % 4;
            uint256 amount = ah.getNextBid(address(nft), SECONDARY_TOKEN) + (seed >> 8) % 1 ether;
            vm.prank(bidders[who]);
            ah.bid{value: amount}(address(nft), SECONDARY_TOKEN, address(0), amount, lid);
            (winner, highBid) = (who, amount);
        }

        uint256 credits;
        for (uint256 i = 0; i < 4; ++i) {
            uint256 credit = ah.claimableFunds(bidders[i], address(0));
            credits += credit;
            uint256 kept = bidders[i].balance + credit;
            assertEq(kept, 1_000 ether - (i == winner ? highBid : 0), "bidder not made whole");
            if (i != 3) assertEq(credit, 0, "EOA refund credited instead of sent");
        }
        assertEq(address(ah).balance, highBid + credits, "escrow != high bid + credits");
    }

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _list(
        uint256 tokenId,
        ListingType type_,
        address currency,
        uint256 openTime,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) internal returns (uint256) {
        vm.prank(nft.ownerOf(tokenId));
        ah.list(
            ListingConfig(
                address(nft),
                tokenId,
                type_,
                payout,
                currency,
                openTime,
                reservePrice,
                duration,
                buyNowPrice,
                address(0)
            )
        );
        return ah.getListing(address(nft), tokenId).id;
    }

    function _bidEth(address bidder, uint256 amount, uint256 lid) internal {
        vm.deal(bidder, bidder.balance + amount);
        vm.prank(bidder);
        ah.bid{value: amount}(address(nft), SECONDARY_TOKEN, address(0), amount, lid);
    }

    function _fund(address who, address currency, uint256 amount) internal {
        if (currency == address(0)) {
            vm.deal(who, who.balance + amount);
        } else {
            IERC20(currency).transfer(who, amount);
            vm.prank(who);
            IERC20(currency).approve(address(ah), type(uint256).max);
        }
    }

    function _balance(address who, address currency) internal view returns (uint256) {
        return currency == address(0) ? who.balance : IERC20(currency).balanceOf(who);
    }

    function _saturatingAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            uint256 c = a + b;
            return c < a ? type(uint256).max : c;
        }
    }
}

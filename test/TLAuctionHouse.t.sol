// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {RoyaltyLookup} from "src/helpers/RoyaltyLookup.sol";
import {IERC20Errors, IERC721Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {ERC721TL} from "tl-creator-contracts/erc-721/ERC721TL.sol";
import {WETH9} from "tl-sol-tools/../test/utils/WETH9.sol";
import {IChainalysisSanctionsOracle, SanctionsCompliance} from "tl-sol-tools/payments/SanctionsCompliance.sol";
import {ITLAuctionHouseEvents, ListingType, Listing} from "src/utils/TLAuctionHouseUtils.sol";
import {Receiver, RevertingReceiver, RevertingBidder, GriefingBidder} from "test/utils/Receiver.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MaliciousERC721} from "test/utils/MaliciousERC721.sol";

contract TLAuctionHouseTest is Test, ITLAuctionHouseEvents {
    address weth;
    TLAuctionHouse ah;
    CreatorLookup cl;
    RoyaltyLookup rl;
    ERC721TL nft;
    MockERC20 coin;

    address receiver;

    address tl = makeAddr("Build Different");
    uint256 basis;
    uint256 feePerc = 100;
    address royaltyEngine = makeAddr("Royalty Engine");
    address oracle = makeAddr("sanctionsss");

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);
    address bsy = address(0xCDB);
    address anon = address(0x404);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    ///////////////////////////////////////////////////////////////////////////
    /// SETUP
    ///////////////////////////////////////////////////////////////////////////

    function setUp() public {
        weth = address(new WETH9());
        cl = new CreatorLookup();
        rl = new RoyaltyLookup(address(this));
        ah = new TLAuctionHouse(address(this), address(0));
        basis = ah.BASIS();
        ah.setWethAddress(weth);
        ah.setProtocolFeeSettings(tl, feePerc);
        ah.setCreatorLookup(address(cl));
        ah.setRoyaltyLookup(address(rl));

        address[] memory empty = new address[](0);

        vm.startPrank(ben);
        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", "", ben, 1_000, ben, empty, false, address(0), address(0));
        nft.mint(ben, "https://arweave.net/NO-BEEF");
        nft.mint(ben, "https://arweave.net/NO-BEEF-2");
        nft.mint(chris, "https://arweave.net/MORE-COFFEE");
        vm.stopPrank();

        coin = new MockERC20(address(this));
        coin.transfer(ben, 10000 ether);
        coin.transfer(chris, 10000 ether);
        coin.transfer(david, 10000 ether);
        coin.transfer(bsy, 10000 ether);
        coin.transfer(anon, 10000 ether);

        receiver = address(new Receiver());

        vm.deal(ben, 10000 ether);
        vm.deal(chris, 10000 ether);
        vm.deal(david, 10000 ether);
        vm.deal(bsy, 10000 ether);
        vm.deal(anon, 10000 ether);
    }

    function test_setUp() public view {
        assertEq(ah.owner(), address(this));
        assertEq(ah.weth(), weth);
        assertEq(ah.protocolFeeBps(), feePerc);
        assertEq(ah.protocolFeeReceiver(), tl);
        assertEq(address(ah.creatorLookup()), address(cl));
        assertEq(address(ah.royaltyLookup()), address(rl));
        assertFalse(ah.paused());
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST ADMIN
    ///////////////////////////////////////////////////////////////////////////

    function test_ownerOnlyAccess(address sender) public {
        vm.assume(sender != address(this));

        // revert for sender (non-owner)
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.pause(true);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.pause(false);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.transferOwnership(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.setWethAddress(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.setProtocolFeeSettings(sender, 500);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.setSanctionsOracle(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.setCreatorLookup(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.setRoyaltyLookup(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        ah.removeProtocolFee(address(nft), 1);
        vm.stopPrank();

        // pass for owner
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), address(this));
        ah.transferOwnership(address(this));
        assertEq(ah.owner(), address(this));

        vm.expectEmit(true, true, true, true);
        emit WethUpdated(weth, address(0));
        ah.setWethAddress(address(0));
        assertEq(ah.weth(), address(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(address(this), 500);
        ah.setProtocolFeeSettings(address(this), 500);
        assertEq(ah.protocolFeeReceiver(), address(this));
        assertEq(ah.protocolFeeBps(), 500);

        ah.setSanctionsOracle(address(this));
        assertEq(address(ah.oracle()), address(this));

        vm.expectEmit(true, true, true, true);
        emit CreatorLookupUpdated(address(cl), address(0));
        ah.setCreatorLookup(address(0));
        assertEq(address(ah.creatorLookup()), address(0));

        vm.expectEmit(true, true, true, true);
        emit RoyaltyLookupUpdated(address(rl), address(0));
        ah.setRoyaltyLookup(address(0));
        assertEq(address(ah.royaltyLookup()), address(0));

        vm.expectEmit(true, true, true, true);
        emit Paused(address(this));
        ah.pause(true);

        vm.expectEmit(true, true, true, true);
        emit Unpaused(address(this));
        ah.pause(false);
    }

    function test_paused() public {
        ah.pause(true);

        vm.startPrank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.bid(address(nft), 1, ben, 100);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.buyNow(address(nft), 1, ben);
        vm.stopPrank();
    }

    function test_ownerConfigErrors() public {
        // zero address for protocol fee recipient
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.setProtocolFeeSettings(address(0), 100);

        // sanctioned protocol fee recipient
        ah.setSanctionsOracle(oracle);
        vm.mockCall(oracle, IChainalysisSanctionsOracle.isSanctioned.selector, abi.encode(true));
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.setProtocolFeeSettings(address(1), 100);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // invalid bps
        vm.expectRevert(TLAuctionHouse.InvalidProtocolFeeBps.selector);
        ah.setProtocolFeeSettings(address(this), 10_001);

        // listing not configured for zero protocol fee override
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.removeProtocolFee(address(nft), 1);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST LIST
    ///////////////////////////////////////////////////////////////////////////

    function test_list_errors() public {
        // set oracle and let most sanctions calls through
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // sanctioned sender
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.list(address(nft), 3, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // check that if sanctions oracle reverts, tx reverts
        vm.clearMockedCalls();
        vm.mockCallRevert(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), "revert");
        vm.prank(ben);
        vm.expectRevert("revert");
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // check that if sanctions oracle is to an EOA that it reverts
        vm.clearMockedCalls();
        vm.prank(ben);
        vm.expectRevert(); // generic revert
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // allow all sanctions calls to pass
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // not token owner
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotTokenOwner.selector);
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // invalid listing type
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.list(address(nft), 1, ListingType.NOT_CONFIGURED, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // ah not approved
        vm.prank(ben);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(ah), 1));
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // approve first token
        vm.prank(ben);
        nft.approve(address(ah), 1);
        vm.prank(ben);
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0); // passes

        // make sure second token can't be transferred
        vm.prank(ben);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(ah), 2));
        ah.list(address(nft), 2, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // approve for all
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(address(nft), 2, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0); // passes

        // nft doesn't transfer
        MaliciousERC721 c = new MaliciousERC721();
        c.mint(ben);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.TokenNotTransferred.selector);
        ah.list(address(c), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);

        // clear mocked calls
        vm.clearMockedCalls();
    }

    function test_list_oldTimestamp() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, true);
        emit ListingConfigured(
            ben,
            address(nft),
            1,
            Listing({
                type_: ListingType.SCHEDULED_AUCTION,
                zeroProtocolFee: false,
                seller: ben,
                payoutReceiver: ben,
                currencyAddress: address(0),
                openTime: block.timestamp,
                reservePrice: 0,
                buyNowPrice: 0,
                highestBid: 0,
                highestBidder: address(0),
                recipient: address(0),
                duration: 24 hours,
                startTime: block.timestamp,
                id: 1
            })
        );
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), 0, 0, 24 hours, 0);
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.SCHEDULED_AUCTION);
        assertEq(l.seller, ben);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, ben);
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, block.timestamp);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 1);
        assertEq(l.startTime, block.timestamp);
        assertEq(l.duration, 24 hours);
    }

    function test_list_scheduledAuction(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, true);
        emit ListingConfigured(
            ben,
            address(nft),
            1,
            Listing({
                type_: ListingType.SCHEDULED_AUCTION,
                zeroProtocolFee: false,
                seller: ben,
                payoutReceiver: payoutReceiver,
                currencyAddress: currencyAddress,
                openTime: block.timestamp + startDelay,
                reservePrice: reservePrice,
                buyNowPrice: 0,
                highestBid: 0,
                highestBidder: address(0),
                recipient: address(0),
                duration: duration,
                startTime: block.timestamp + startDelay,
                id: 1
            })
        );
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.SCHEDULED_AUCTION);
        assertEq(l.seller, ben);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, payoutReceiver);
        assertEq(l.currencyAddress, currencyAddress);
        assertEq(l.openTime, block.timestamp + startDelay);
        assertEq(l.reservePrice, reservePrice);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 1);
        assertEq(l.startTime, block.timestamp + startDelay);
        assertEq(l.duration, duration);
    }

    function test_list_reserveAuction(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, true);
        emit ListingConfigured(
            ben,
            address(nft),
            1,
            Listing({
                type_: ListingType.RESERVE_AUCTION,
                zeroProtocolFee: false,
                seller: ben,
                payoutReceiver: payoutReceiver,
                currencyAddress: currencyAddress,
                openTime: block.timestamp + startDelay,
                reservePrice: reservePrice,
                buyNowPrice: 0,
                highestBid: 0,
                highestBidder: address(0),
                recipient: address(0),
                duration: duration,
                startTime: 0,
                id: 1
            })
        );
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.RESERVE_AUCTION);
        assertEq(l.seller, ben);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, payoutReceiver);
        assertEq(l.currencyAddress, currencyAddress);
        assertEq(l.openTime, block.timestamp + startDelay);
        assertEq(l.reservePrice, reservePrice);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 1);
        assertEq(l.startTime, 0);
        assertEq(l.duration, duration);
    }

    function test_list_reserveAuctionPlusBuyNow(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, true);
        emit ListingConfigured(
            ben,
            address(nft),
            1,
            Listing({
                type_: ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                zeroProtocolFee: false,
                seller: ben,
                payoutReceiver: payoutReceiver,
                currencyAddress: currencyAddress,
                openTime: block.timestamp + startDelay,
                reservePrice: reservePrice,
                buyNowPrice: buyNowPrice,
                highestBid: 0,
                highestBidder: address(0),
                recipient: address(0),
                duration: duration,
                startTime: 0,
                id: 1
            })
        );
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW);
        assertEq(l.seller, ben);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, payoutReceiver);
        assertEq(l.currencyAddress, currencyAddress);
        assertEq(l.openTime, block.timestamp + startDelay);
        assertEq(l.reservePrice, reservePrice);
        assertEq(l.buyNowPrice, buyNowPrice);
        assertEq(l.id, 1);
        assertEq(l.startTime, 0);
        assertEq(l.duration, duration);
    }

    function test_list_buyNow(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, true);
        emit ListingConfigured(
            ben,
            address(nft),
            1,
            Listing({
                type_: ListingType.BUY_NOW,
                zeroProtocolFee: false,
                seller: ben,
                payoutReceiver: payoutReceiver,
                currencyAddress: currencyAddress,
                openTime: block.timestamp + startDelay,
                reservePrice: 0,
                buyNowPrice: buyNowPrice,
                highestBid: 0,
                highestBidder: address(0),
                recipient: address(0),
                duration: 0,
                startTime: 0,
                id: 1
            })
        );
        ah.list(
            address(nft),
            1,
            ListingType.BUY_NOW,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.BUY_NOW);
        assertEq(l.seller, ben);
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, payoutReceiver);
        assertEq(l.currencyAddress, currencyAddress);
        assertEq(l.openTime, block.timestamp + startDelay);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, buyNowPrice);
        assertEq(l.id, 1);
        assertEq(l.startTime, 0);
        assertEq(l.duration, 0);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST DELIST
    ///////////////////////////////////////////////////////////////////////////

    function test_delist_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0);
        vm.stopPrank();

        // not seller
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.delist(address(nft), 1);

        // listing not configured
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.delist(address(nft), 2);

        // auction started
        vm.deal(chris, 0.1 ether);
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.delist(address(nft), 1);
    }

    function test_delist_scheduledAuction(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.startTime, 0);
        assertEq(l.duration, 0);
    }

    function test_delist_reserveAuction(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.startTime, 0);
        assertEq(l.duration, 0);
    }

    function test_delist_reserveAuctionPlusBuyNow(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.startTime, 0);
        assertEq(l.duration, 0);
    }

    function test_delist_buyNow(
        address payoutReceiver,
        address currencyAddress,
        uint64 startDelay,
        uint256 reservePrice,
        uint256 duration,
        uint256 buyNowPrice
    ) public {
        // limit inputs
        vm.assume(payoutReceiver != address(0));

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.BUY_NOW,
            payoutReceiver,
            currencyAddress,
            block.timestamp + startDelay,
            reservePrice,
            duration,
            buyNowPrice
        );
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        Listing memory l = ah.getListing(address(nft), 1);
        assertTrue(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertFalse(l.zeroProtocolFee);
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.startTime, 0);
        assertEq(l.duration, 0);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST BID ETH
    ///////////////////////////////////////////////////////////////////////////

    function test_first_bid_eth_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(0),
            block.timestamp + 1 hours,
            0.01 ether,
            24 hours,
            0
        );
        vm.stopPrank();

        // set oracle and let most sanctions calls through
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // deal 0.1 ether to ben, chris, and anon
        vm.deal(ben, 0.1 ether);
        vm.deal(chris, 0.1 ether);
        vm.deal(anon, 0.1 ether);

        // sanctioned sender
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether);

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, anon, 0.1 ether);

        // listing not configured
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid{value: 0.1 ether}(address(nft), 2, chris, 0.1 ether);

        // buy now configured
        vm.prank(ben);
        ah.list(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 24 hours, 0.1 ether);

        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid{value: 0.1 ether}(address(nft), 2, chris, 0.1 ether);

        // listing not open
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);

        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // bid under reserve price
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid{value: 0.009 ether}(address(nft), 1, chris, 0.009 ether);

        // funds not attached
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.bid{value: 0 ether}(address(nft), 1, chris, 0.1 ether);

        // clear mocks
        vm.clearMockedCalls();
    }

    function test_bid_eth_revertingBidder() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // create reverting bidder and bid
        RevertingBidder bidder = new RevertingBidder(address(ah));
        vm.prank(chris);
        bidder.bid{value: 0.01 ether}(address(nft), 1, 0.01 ether);

        // chris bids and has the highest bid
        vm.prank(chris);
        ah.bid{value: 0.02 ether}(address(nft), 1, chris, 0.02 ether);

        // ensure auction values are correct
        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.highestBid, 0.02 ether);
        assertEq(l.highestBidder, chris);

        // reverting bidder gets funds back as WETH
        assertEq(address(bidder).balance, 0);
        assertEq(WETH9(payable(weth)).balanceOf(address(bidder)), 0.01 ether);
    }

    function test_bid_eth_griefingBidder() public {
        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // create griefing bidder and bid
        GriefingBidder bidder = new GriefingBidder(address(ah));
        vm.prank(chris);
        bidder.bid{value: 0.01 ether}(address(nft), 1, 0.01 ether);

        // chris bids and has the highest bid
        vm.prank(chris);
        ah.bid{value: 0.02 ether}(address(nft), 1, chris, 0.02 ether);

        // ensure auction values are correct
        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.highestBid, 0.02 ether);
        assertEq(l.highestBidder, chris);

        // griefing bidder gets funds back as WETH
        assertEq(address(bidder).balance, 0);
        assertEq(WETH9(payable(weth)).balanceOf(address(bidder)), 0.01 ether);
    }

    function test_bid_scheduledAuctionEnded() public {
        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // chris bids and it reverts
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.bid{value: 0.02 ether}(address(nft), 1, chris, 0.02 ether);

        // can't settle auction
        vm.expectRevert(TLAuctionHouse.AuctionNotStarted.selector);
        ah.settleAuction(address(nft), 1);

        // can cancel auction
        vm.prank(ben);
        ah.delist(address(nft), 1);
    }

    function _check_auction_data(address nftAddress, uint256 tokenId, Listing memory l) private view {
        // ensure auction values are correct
        Listing memory l2 = ah.getListing(nftAddress, tokenId);
        assert(l.type_ == l2.type_);
        assertEq(l.seller, l2.seller);
        assertEq(l.payoutReceiver, l2.payoutReceiver);
        assertEq(l.currencyAddress, l2.currencyAddress);
        assertEq(l.openTime, l2.openTime);
        assertEq(l.reservePrice, l2.reservePrice);
        assertEq(l.buyNowPrice, l2.buyNowPrice);
        assertEq(l.id, l2.id);
        assertEq(l.highestBidder, l2.highestBidder);
        assertEq(l.highestBid, l2.highestBid);
        assertEq(l.recipient, l2.recipient);
        assertEq(l.duration, l2.duration);
        assertEq(l.startTime, l2.startTime);
    }

    function _bid_eth(address nftAddress, uint256 tokenId, address sender, address recipient, uint256 amount) private {
        // get existing data
        Listing memory l = ah.getListing(nftAddress, tokenId);

        uint256 ahPrevBalance = address(ah).balance;
        uint256 senderPrevBalance = sender.balance;
        uint256 prevBidderBalance = l.highestBidder.balance;
        uint256 prevHighestBid = l.highestBid;
        address prevBidder = l.highestBidder;

        // adjust data
        l.highestBidder = sender;
        l.highestBid = amount;
        l.recipient = recipient;
        if (l.startTime == 0) {
            l.startTime = block.timestamp;
        }
        uint256 timeLeft = l.startTime + l.duration - block.timestamp;
        if (timeLeft < 300) {
            l.duration += 300 - timeLeft;
        }

        // bid
        vm.prank(sender);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(sender, nftAddress, tokenId, l);
        ah.bid{value: amount}(address(nft), tokenId, recipient, amount);

        // ensure auction values are correct
        _check_auction_data(nftAddress, tokenId, l);

        // esnure funds transfer
        assertEq(address(ah).balance - ahPrevBalance, amount - prevHighestBid);
        assertEq(senderPrevBalance - sender.balance, amount);
        if (prevBidder != address(0)) assertEq(prevBidder.balance - prevBidderBalance, prevHighestBid);
    }

    function _settle_auction(address nftAddress, uint256 tokenId) private {
        Listing memory l = ah.getListing(nftAddress, tokenId);

        uint256 protocolFee = l.highestBid * ah.protocolFeeBps() / ah.BASIS();

        bool primarySale = ah.getIfPrimarySale(nftAddress, tokenId);
        (address payable[] memory recipients, uint256[] memory amounts) =
            ah.getRoyalty(nftAddress, tokenId, l.highestBid - protocolFee);

        uint256[] memory prevValues = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            prevValues[i] = recipients[i].balance;
        }

        uint256 ahPrevBalance = address(ah).balance;
        uint256 tlPrevBalance = tl.balance;
        uint256 payoutReceiverPrevBalance = l.payoutReceiver.balance;

        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), tokenId, l);
        ah.settleAuction(address(nft), tokenId);

        uint256 remainingValue = l.highestBid - protocolFee;
        assertEq(ahPrevBalance - address(ah).balance, l.highestBid);
        assertEq(tl.balance - tlPrevBalance, protocolFee);
        if (!primarySale) {
            for (uint256 i = 0; i < recipients.length; i++) {
                assertEq(recipients[i].balance - prevValues[i], amounts[i]);
                remainingValue -= amounts[i];
            }
        }
        assertEq(l.payoutReceiver.balance - payoutReceiverPrevBalance, remainingValue);
        assertEq(ERC721TL(nftAddress).ownerOf(tokenId), l.recipient);

        // ensure listing and auction are cleared from storage
        l = ah.getListing(nftAddress, tokenId);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);
    }

    function test_eth_scheduledAuction_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_scheduledAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_scheduledAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.SCHEDULED_AUCTION,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_scheduledAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.SCHEDULED_AUCTION,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuction_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuctionPlusBuyNow_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuctionPlusBuyNow_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuctionPlusBuyNow_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuctionPlusBuyNow_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // remove royalty lookup
        ah.setRoyaltyLookup(address(0));

        // deal ether to ben, chris, bsy, and anon
        vm.deal(ben, 1000 ether);
        vm.deal(chris, 1000 ether);
        vm.deal(bsy, 1000 ether);
        vm.deal(address(0), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            chris,
            address(0),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_eth(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST BID ERC-20
    ///////////////////////////////////////////////////////////////////////////

    function test_first_bid_erc20_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(coin),
            block.timestamp + 1 hours,
            0.01 ether,
            24 hours,
            0
        );
        vm.stopPrank();

        // set oracle and let most sanctions calls through
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // sanctioned sender
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.bid(address(nft), 1, chris, 0.1 ether);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.bid(address(nft), 1, address(0), 0.1 ether);

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.bid(address(nft), 1, anon, 0.1 ether);

        // listing not configured
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid(address(nft), 2, chris, 0.1 ether);

        // buy now configured
        vm.prank(ben);
        ah.list(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 24 hours, 0.1 ether);

        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid(address(nft), 2, chris, 0.1 ether);

        // listing not open
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
        ah.bid(address(nft), 1, chris, 0.1 ether);

        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // bid under reserve price
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), 1, chris, 0.009 ether);

        // funds attached
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector); // coin reverts due to not being approved
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);

        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.bid(address(nft), 1, chris, 0.1 ether);

        // not enought coin supply
        vm.startPrank(chris);
        coin.approve(address(ah), 10000000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 10000 ether, 10000000 ether)
        ); // coin reverts due to insufficient balance
        ah.bid(address(nft), 1, chris, 10000000 ether);

        // clear mocks
        vm.clearMockedCalls();
    }

    function _bid_erc20(address nftAddress, uint256 tokenId, address sender, address recipient, uint256 amount)
        private
    {
        // get existing data
        Listing memory l = ah.getListing(nftAddress, tokenId);

        uint256 ahPrevBalance = coin.balanceOf(address(ah));
        uint256 senderPrevBalance = coin.balanceOf(sender);
        uint256 prevBidderBalance = coin.balanceOf(l.highestBidder);
        uint256 prevHighestBid = l.highestBid;
        address prevBidder = l.highestBidder;

        // adjust data
        l.highestBidder = sender;
        l.highestBid = amount;
        l.recipient = recipient;
        if (l.startTime == 0) {
            l.startTime = block.timestamp;
        }
        uint256 timeLeft = l.startTime + l.duration - block.timestamp;
        if (timeLeft < 300) {
            l.duration += 300 - timeLeft;
        }

        // bid
        vm.prank(sender);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(sender, nftAddress, tokenId, l);
        ah.bid(address(nft), tokenId, recipient, amount);

        // ensure auction values are correct
        _check_auction_data(nftAddress, tokenId, l);

        // esnure funds transfer
        assertEq(coin.balanceOf(address(ah)) - ahPrevBalance, amount - prevHighestBid);
        assertEq(senderPrevBalance - coin.balanceOf(sender), amount);
        if (prevBidder != address(0)) assertEq(coin.balanceOf(prevBidder) - prevBidderBalance, prevHighestBid);
    }

    function _settle_auction_erc20(address nftAddress, uint256 tokenId) private {
        Listing memory l = ah.getListing(nftAddress, tokenId);

        uint256 protocolFee = l.highestBid * ah.protocolFeeBps() / ah.BASIS();

        bool primarySale = ah.getIfPrimarySale(nftAddress, tokenId);
        (address payable[] memory recipients, uint256[] memory amounts) =
            ah.getRoyalty(nftAddress, tokenId, l.highestBid - protocolFee);

        uint256[] memory prevValues = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            prevValues[i] = coin.balanceOf(recipients[i]);
        }

        uint256 ahPrevBalance = coin.balanceOf(address(ah));
        uint256 tlPrevBalance = coin.balanceOf(tl);
        uint256 payoutReceiverPrevBalance = coin.balanceOf(l.payoutReceiver);

        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), tokenId, l);
        ah.settleAuction(address(nft), tokenId);

        uint256 remainingValue = l.highestBid - protocolFee;
        assertEq(ahPrevBalance - coin.balanceOf(address(ah)), l.highestBid);
        assertEq(coin.balanceOf(tl) - tlPrevBalance, protocolFee);
        if (!primarySale) {
            for (uint256 i = 0; i < recipients.length; i++) {
                assertEq(coin.balanceOf(recipients[i]) - prevValues[i], amounts[i]);
                remainingValue -= amounts[i];
            }
        }
        assertEq(coin.balanceOf(l.payoutReceiver) - payoutReceiverPrevBalance, remainingValue);
        assertEq(ERC721TL(nftAddress).ownerOf(tokenId), l.recipient);

        // ensure listing and auction are cleared from storage
        l = ah.getListing(nftAddress, tokenId);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);
    }

    function test_erc20_scheduledAuction_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_scheduledAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_scheduledAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.SCHEDULED_AUCTION,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_scheduledAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.SCHEDULED_AUCTION,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuction_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuctionPlusBuyNow_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuctionPlusBuyNow_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, chris, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 1, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuctionPlusBuyNow_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuctionPlusBuyNow_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration,
        bool bidderSameAsRecipient
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }

        if (duration > 300 days) {
            duration %= 300 days;
        }

        // set royalty lookup to address(0)
        ah.setRoyaltyLookup(address(0));

        // approve auction house
        vm.prank(ben);
        coin.approve(address(ah), 10000 ether);
        vm.prank(chris);
        coin.approve(address(ah), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(ah), 10000 ether);
        vm.prank(anon);
        coin.approve(address(ah), 10000 ether);
        vm.prank(david);
        coin.approve(address(ah), 10000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            chris,
            address(coin),
            block.timestamp + startDelay,
            reservePrice,
            duration,
            0
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, ben, reservePrice);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, david, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        address recipient = bidderSameAsRecipient ? bsy : anon;
        _bid_erc20(address(nft), 3, bsy, recipient, 777 ether);

        // bid under highest bid
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 700 ether);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, david, 900 ether);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST SETTLE AUCTION
    ///////////////////////////////////////////////////////////////////////////

    function test_settleAuction_errors() public {
        // list nfts
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.SCHEDULED_AUCTION,
            ben,
            address(0),
            block.timestamp + 24 hours,
            0.01 ether,
            24 hours,
            0
        );
        ah.list(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0);
        vm.stopPrank();

        // listing not configured
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.settleAuction(address(nft), 3);

        // buy now configured
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.settleAuction(address(nft), 2);

        // auction hasn't started
        vm.expectRevert(TLAuctionHouse.AuctionNotStarted.selector);
        ah.settleAuction(address(nft), 1);

        // bid on auction for nft 1
        vm.warp(block.timestamp + 24 hours);
        vm.deal(chris, 0.1 ether);
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);

        // auction not ended
        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), 1);

        vm.warp(block.timestamp + 24 hours);

        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), 1);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST SETTLE UP FUNCTION
    ///////////////////////////////////////////////////////////////////////////

    function test_settleUp_royaltyLookupReverts() public {
        // mock royalty lookup
        vm.mockCallRevert(address(rl), RoyaltyLookup.getRoyalty.selector, "revert");
        vm.mockCallRevert(address(rl), RoyaltyLookup.getRoyaltyView.selector, "revert");

        // ensure 0 royalties returned
        (address payable[] memory r,) = ah.getRoyalty(address(nft), 3, 10_000);
        assertEq(r.length, 0);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, david, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // get previous balances
        uint256 ahPrevBalance = address(ah).balance;
        uint256 chrisPrevBalance = chris.balance;
        uint256 benPrevBalance = ben.balance;

        // settle the auction
        ah.settleAuction(address(nft), 3);

        // check balances
        assertEq(ahPrevBalance - address(ah).balance, 0.1 ether);
        assertEq(ben.balance - benPrevBalance, 0); // royalties not paid due to revert
        assertEq(chris.balance - chrisPrevBalance, 0.1 ether);

        vm.clearMockedCalls();
    }

    function test_settleUp_royaltyArrayMistmatch() public {
        // mock royalty lookup
        address payable[] memory r = new address payable[](1);
        r[0] = payable(address(1));
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0;
        amts[1] = 1;
        vm.mockCall(address(rl), RoyaltyLookup.getRoyalty.selector, abi.encode(r, amts));

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, david, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // get previous balances
        uint256 ahPrevBalance = address(ah).balance;
        uint256 chrisPrevBalance = chris.balance;
        uint256 benPrevBalance = ben.balance;

        // settle the auction
        ah.settleAuction(address(nft), 3);

        // check balances
        assertEq(ahPrevBalance - address(ah).balance, 0.1 ether);
        assertEq(ben.balance - benPrevBalance, 0); // royalties not paid due to mismatch
        assertEq(chris.balance - chrisPrevBalance, 0.1 ether);

        vm.clearMockedCalls();
    }

    function test_settleUp_sanctionedAddress() public {
        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, david, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // get previous balances
        uint256 ahPrevBalance = address(ah).balance;
        uint256 chrisPrevBalance = chris.balance;
        uint256 benPrevBalance = ben.balance;

        // set sanctions oracle
        ah.setSanctionsOracle(oracle);

        // mock sanctions call to return true for sanctioned address
        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));

        // settle the auction
        ah.settleAuction(address(nft), 3);

        // check balances
        assertEq(ahPrevBalance - address(ah).balance, 0.1 ether);
        assertEq(ben.balance - benPrevBalance, 0); // royalties not paid due to sanctions
        assertEq(chris.balance - chrisPrevBalance, 0.1 ether);

        vm.clearMockedCalls();
    }

    function test_settleUp_bigRoyalties() public {
        // mock royalty lookup
        address payable[] memory r = new address payable[](1);
        r[0] = payable(address(1));
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;
        vm.mockCall(address(rl), RoyaltyLookup.getRoyalty.selector, abi.encode(r, amts));

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, david, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // get previous balances
        uint256 ahPrevBalance = address(ah).balance;
        uint256 chrisPrevBalance = chris.balance;
        uint256 benPrevBalance = ben.balance;

        // settle the auction
        ah.settleAuction(address(nft), 3);

        // check balances
        assertEq(ahPrevBalance - address(ah).balance, 0.1 ether);
        assertEq(ben.balance - benPrevBalance, 0); // royalties not paid due to trying to payout too much
        assertEq(chris.balance - chrisPrevBalance, 0.1 ether);

        vm.clearMockedCalls();
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST BUY NOW ETH
    ///////////////////////////////////////////////////////////////////////////

    function test_buyNow_eth_errors() public {
        // set oracle and let most sanctions calls through
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // deal 0.1 ether to ben, chris, and anon
        vm.deal(ben, 1 ether);
        vm.deal(chris, 1 ether);
        vm.deal(anon, 1 ether);

        // sanctioned sender
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.buyNow(address(nft), 1, chris);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, address(0));

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, anon);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(false)
        );

        // not configured listing
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 1, chris);

        // configured as scheduled auction
        vm.prank(chris);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(chris);
        ah.list(
            address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(0), block.timestamp, 0.01 ether, 24 hours, 0
        );

        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 3, ben);

        // configured as reserve auction
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0);

        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 2, chris);

        vm.prank(ben);
        ah.delist(address(nft), 2);

        // list nft 1 as reserve + buy now
        vm.prank(ben);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(0),
            block.timestamp + 24 hours,
            0.01 ether,
            24 hours,
            0.1 ether
        );

        // list nft 2 as buy now
        vm.prank(ben);
        ah.list(
            address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp + 24 hours, 0, 24 hours, 0.1 ether
        );

        // trying to buy too soon
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, chris);

        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.1 ether}(address(nft), 2, chris);

        // warp
        vm.warp(block.timestamp + 24 hours);

        // not enough eth attached
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 1, chris);

        // too much eth attached
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 1 ether}(address(nft), 2, chris);

        // auction in progress
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, chris, 0.1 ether);

        vm.prank(anon);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, anon);
    }

    function test_reservePlusBuyNow_eth_primary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(0),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // primary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_reservePlusBuyNow_eth_primary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(0),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // primary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_reservePlusBuyNow_eth_secondary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(0),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, amounts[0]); // secondary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_reservePlusBuyNow_eth_secondary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(0),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        // (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        // remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // royalty lookup skipped
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_buyNow_eth_primary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(address(nft), 1, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice);
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // primary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_buyNow_eth_primary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(address(nft), 1, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice);
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // primary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_buyNow_eth_secondary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(address(nft), 3, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice);
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, amounts[0]); // secondary sale
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_buyNow_eth_secondary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // deal eth to buyer
        vm.deal(buyer, 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(address(nft), 3, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice);
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = buyer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        // (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        // remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - buyer.balance, buyNowPrice);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, 0); // royalty lookup skipped
        assertEq(anon.balance - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// TEST BUY NOW ERC-20
    ///////////////////////////////////////////////////////////////////////////

    function test_buyNow_erc20_errors() public {
        // set oracle and let most sanctions calls through
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // sanctioned sender
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.buyNow(address(nft), 1, chris);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, address(0));

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, anon);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(false)
        );

        // not configured listing
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 1, chris);

        // configured as scheduled auction
        vm.prank(chris);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(chris);
        ah.list(
            address(nft),
            3,
            ListingType.SCHEDULED_AUCTION,
            chris,
            address(coin),
            block.timestamp,
            0.01 ether,
            24 hours,
            0
        );

        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 3, ben);

        // configured as reserve auction
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(
            address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(coin), block.timestamp, 0.01 ether, 24 hours, 0
        );

        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 2, chris);

        vm.prank(ben);
        ah.delist(address(nft), 2);

        // list nft 1 as reserve + buy now
        vm.prank(ben);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            ben,
            address(coin),
            block.timestamp + 24 hours,
            0.01 ether,
            24 hours,
            0.1 ether
        );

        // list nft 2 as buy now
        vm.prank(ben);
        ah.list(
            address(nft), 2, ListingType.BUY_NOW, ben, address(coin), block.timestamp + 24 hours, 0, 24 hours, 0.1 ether
        );

        // trying to buy too soon
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);

        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 2, chris);

        // warp
        vm.warp(block.timestamp + 24 hours);

        // eth attached
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 1, chris);

        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 2, chris);

        // not enough coin allowance
        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.buyNow(address(nft), 1, chris);

        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.buyNow(address(nft), 2, chris);

        // not enought coin supply
        vm.startPrank(chris);
        coin.approve(address(ah), 10000 ether);
        coin.transfer(address(this), 10000 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether)); // coin reverts due to insufficient balance
        ah.buyNow(address(nft), 1, chris);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether)); // coin reverts due to insufficient balance
        ah.buyNow(address(nft), 2, chris);
        vm.stopPrank();

        coin.transfer(chris, 10000 ether);

        // auction in progress
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0.1 ether);

        vm.prank(anon);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.buyNow(address(nft), 1, anon);
    }

    function test_reservePlusBuyNow_erc20_primary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(coin),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // primary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_reservePlusBuyNow_erc20_primary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            1,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(coin),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // primary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_reservePlusBuyNow_erc20_secondary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(coin),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, amounts[0]); // secondary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_reservePlusBuyNow_erc20_secondary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft),
            3,
            ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
            anon,
            address(coin),
            block.timestamp + startDelay,
            0,
            0,
            buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        // (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        // remainingBalance -= amounts[0];
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // royalty lookup skipped
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_buyNow_erc20_primary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 1, ListingType.BUY_NOW, anon, address(coin), block.timestamp + startDelay, 0, 0, buyNowPrice
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // primary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed

        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_buyNow_erc20_primary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 1, ListingType.BUY_NOW, anon, address(coin), block.timestamp + startDelay, 0, 0, buyNowPrice
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 1);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;

        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // primary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(1), recipient);

        // ensure data is zeroed
        l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, chris, 0);

        // try buying
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris);
    }

    function test_buyNow_erc20_secondary_royaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.BUY_NOW, anon, address(coin), block.timestamp + startDelay, 0, 0, buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        remainingBalance -= amounts[0];
        assertEq(address(ah).balance, 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, amounts[0]); // secondary sale
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed
        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }

    function test_buyNow_erc20_secondary_noRoyaltyLookup(
        uint64 startDelay,
        uint256 buyNowPrice,
        address buyer,
        address recipient
    ) public {
        // limit fuzz variables
        if (buyNowPrice > 500 ether) {
            buyNowPrice %= 500 ether;
        }

        vm.assume(buyer != ben && buyer != tl && buyer != anon && buyer != address(0) && buyer != address(ah));
        vm.assume(recipient != address(0));

        // set royalty lookjup to address(0)
        ah.setRoyaltyLookup(address(0));

        // ben sends coins to buyer
        vm.prank(ben);
        coin.transfer(buyer, 1000 ether);

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            address(nft), 3, ListingType.BUY_NOW, anon, address(coin), block.timestamp + startDelay, 0, 0, buyNowPrice
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient);
            vm.warp(block.timestamp + startDelay);
        }

        // get listing
        Listing memory l = ah.getListing(address(nft), 3);

        // cache funds values
        uint256 prevBuyerBalance = coin.balanceOf(buyer);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevAnonBalance = coin.balanceOf(anon);

        // buy now
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        // (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, remainingBalance);
        // remainingBalance -= amounts[0];
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(prevBuyerBalance - coin.balanceOf(buyer), buyNowPrice);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 0); // royalty lookup skipped
        assertEq(coin.balanceOf(anon) - prevAnonBalance, remainingBalance);

        // ensure nft transferred
        assertEq(nft.ownerOf(3), recipient);

        // ensure data is zeroed
        l = ah.getListing(address(nft), 3);
        assert(l.type_ == ListingType.NOT_CONFIGURED);
        assertEq(l.seller, address(0));
        assertEq(l.payoutReceiver, address(0));
        assertEq(l.currencyAddress, address(0));
        assertEq(l.openTime, 0);
        assertEq(l.reservePrice, 0);
        assertEq(l.buyNowPrice, 0);
        assertEq(l.id, 0);
        assertEq(l.highestBidder, address(0));
        assertEq(l.highestBid, 0);
        assertEq(l.recipient, address(0));
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);

        // try bidding
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, ben, 0);

        // try buying again
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std-1.9.4/Test.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {TransferHelper} from "src/lib/TransferHelper.sol";
import {CurrencyAllowlist} from "src/lib/CurrencyAllowlist.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {RoyaltyLookup} from "src/helpers/RoyaltyLookup.sol";
import {IERC20Errors, IERC721Errors} from "@openzeppelin-contracts-5.6.1/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/utils/PausableUpgradeable.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {IChainalysisSanctionsOracle, SanctionsCompliance} from "src/lib/SanctionsCompliance.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {ITLAuctionHouseEvents, ListingType, Listing, ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";
import {Receiver, RevertingReceiver, RevertingBidder, GriefingBidder} from "test/utils/Receiver.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MaliciousERC721} from "test/utils/MaliciousERC721.sol";
import {BadERC721} from "test/utils/BadERC721.sol";
import {BlocklistERC20} from "test/utils/BlocklistERC20.sol";
import {FeeOnTransferERC20} from "test/utils/FeeOnTransferERC20.sol";

contract TLAuctionHouseTest is Test, ITLAuctionHouseEvents {
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

    uint256 lid; // listing id to bid on, fetched ahead of any pranks or expected reverts

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _cfg(
        address nftAddress,
        uint256 tokenId,
        ListingType type_,
        address payoutReceiver,
        address currencyAddress,
        uint256 openTime,
        uint256 reservePrice,
        uint256 auctionDuration,
        uint256 buyNowPrice
    ) internal pure returns (ListingConfig memory) {
        return _cfg(
            nftAddress,
            tokenId,
            type_,
            payoutReceiver,
            currencyAddress,
            openTime,
            reservePrice,
            auctionDuration,
            buyNowPrice,
            address(0)
        );
    }

    function _cfg(
        address nftAddress,
        uint256 tokenId,
        ListingType type_,
        address payoutReceiver,
        address currencyAddress,
        uint256 openTime,
        uint256 reservePrice,
        uint256 auctionDuration,
        uint256 buyNowPrice,
        address recipient
    ) internal pure returns (ListingConfig memory) {
        return ListingConfig({
            nftAddress: nftAddress,
            tokenId: tokenId,
            type_: type_,
            payoutReceiver: payoutReceiver,
            currencyAddress: currencyAddress,
            openTime: openTime,
            reservePrice: reservePrice,
            auctionDuration: auctionDuration,
            buyNowPrice: buyNowPrice,
            recipient: recipient
        });
    }

    /////////////////////////////////////////////////////////////////////
    // SETUP
    /////////////////////////////////////////////////////////////////////

    function setUp() public {
        cl = new CreatorLookup();
        rl = new RoyaltyLookup(address(this));
        ah = new TLAuctionHouse(address(this), address(0));
        basis = ah.BASIS();
        ah.setProtocolFeeSettings(tl, feePerc);
        ah.setCreatorLookup(address(cl));
        ah.setRoyaltyLookup(address(rl));

        address[] memory empty = new address[](0);

        vm.startPrank(ben);
        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", ben, 1_000, ben, empty, false, address(0), 0, address(0));
        nft.mint(ben, "https://arweave.net/NO-BEEF");
        nft.mint(ben, "https://arweave.net/NO-BEEF-2");
        nft.mint(chris, "https://arweave.net/MORE-COFFEE");
        vm.stopPrank();

        coin = new MockERC20(address(this));
        ah.setCurrencyAllowed(address(coin), true);
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
        assertEq(ah.protocolFeeBps(), feePerc);
        assertEq(ah.protocolFeeReceiver(), tl);
        assertEq(address(ah.creatorLookup()), address(cl));
        assertEq(address(ah.royaltyLookup()), address(rl));
        assertFalse(ah.paused());
    }

    /////////////////////////////////////////////////////////////////////
    // TEST ADMIN
    /////////////////////////////////////////////////////////////////////

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

        // pass for owner (two step ownership transfer)
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferStarted(address(this), address(this));
        ah.transferOwnership(address(this));
        assertEq(ah.pendingOwner(), address(this));
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), address(this));
        ah.acceptOwnership();
        assertEq(ah.owner(), address(this));
        assertEq(ah.pendingOwner(), address(0));

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
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(0),
                block.timestamp,
                1,
                24 hours,
                1 ether
            )
        );
        vm.stopPrank();

        ah.pause(true);

        vm.startPrank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.list(_cfg(address(nft), 2, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.bid(address(nft), 1, address(0), 100, lid);
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.buyNow(address(nft), 1, ben, address(0), type(uint256).max, lid);

        // sellers can still take back listings without bids
        ah.delist(address(nft), 1);
        assertEq(nft.ownerOf(1), ben);
        vm.stopPrank();
    }

    function test_ownerConfigErrors() public {
        // zero address for protocol fee recipient
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.setProtocolFeeSettings(address(0), 100);

        // sanctioned protocol fee recipient
        ah.setSanctionsOracle(oracle);
        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.setProtocolFeeSettings(address(1), 100);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // invalid bps
        vm.expectRevert(TLAuctionHouse.InvalidProtocolFeeBps.selector);
        ah.setProtocolFeeSettings(address(this), 10_001);
        uint256 maxFeeBps = ah.MAX_PROTOCOL_FEE_BPS();
        vm.expectRevert(TLAuctionHouse.InvalidProtocolFeeBps.selector);
        ah.setProtocolFeeSettings(address(this), maxFeeBps + 1);
        ah.setProtocolFeeSettings(address(this), maxFeeBps);

        // listing not configured for zero protocol fee override
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.removeProtocolFee(address(nft), 1);
    }

    /////////////////////////////////////////////////////////////////////
    // TEST LIST
    /////////////////////////////////////////////////////////////////////

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
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // sanctioned payout receiver
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.list(_cfg(address(nft), 3, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // check that if sanctions oracle reverts, tx reverts
        vm.clearMockedCalls();
        vm.mockCallRevert(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), "revert");
        vm.prank(ben);
        vm.expectRevert("revert");
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // check that if sanctions oracle is to an EOA that it reverts
        vm.clearMockedCalls();
        vm.prank(ben);
        vm.expectRevert(); // generic revert
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // allow all sanctions calls to pass
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );

        // not token owner
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotTokenOwner.selector);
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // invalid listing type
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.list(_cfg(address(nft), 1, ListingType.NOT_CONFIGURED, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // ah not approved
        vm.prank(ben);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(ah), 1));
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // approve first token
        vm.prank(ben);
        nft.approve(address(ah), 1);
        vm.prank(ben);
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0)); // passes

        // make sure second token can't be transferred
        vm.prank(ben);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(ah), 2));
        ah.list(_cfg(address(nft), 2, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

        // approve for all
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(_cfg(address(nft), 2, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0)); // passes

        // nft doesn't transfer
        MaliciousERC721 c = new MaliciousERC721();
        c.mint(ben);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.NftTransferFailed.selector);
        ah.list(_cfg(address(c), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));

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
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), 0, 0, 24 hours, 0));
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

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
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

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
            _cfg(
                address(nft),
                1,
                ListingType.BUY_NOW,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
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

    /////////////////////////////////////////////////////////////////////
    // TEST DELIST
    /////////////////////////////////////////////////////////////////////

    function test_delist_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, anon, address(0), block.timestamp, 0, 24 hours, 0));
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
        lid = ah.getListing(address(nft), 1).id;
        vm.deal(chris, 0.1 ether);
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, lid);
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
        );
        Listing memory l = ah.getListing(address(nft), 1);
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1, l);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        l = ah.getListing(address(nft), 1);
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
        );
        Listing memory l = ah.getListing(address(nft), 1);
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1, l);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        l = ah.getListing(address(nft), 1);
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
        );
        Listing memory l = ah.getListing(address(nft), 1);
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1, l);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        l = ah.getListing(address(nft), 1);
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
        duration = bound(duration, 0, ah.MAX_AUCTION_DURATION());
        ah.setCurrencyAllowed(currencyAddress, true);

        // list & delist
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.BUY_NOW,
                payoutReceiver,
                currencyAddress,
                block.timestamp + startDelay,
                reservePrice,
                duration,
                buyNowPrice
            )
        );
        Listing memory l = ah.getListing(address(nft), 1);
        vm.expectEmit(true, true, true, true);
        emit ListingCanceled(ben, address(nft), 1, l);
        ah.delist(address(nft), 1);
        vm.stopPrank();

        // check values
        l = ah.getListing(address(nft), 1);
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

    /////////////////////////////////////////////////////////////////////
    // TEST BID ETH
    /////////////////////////////////////////////////////////////////////

    function test_first_bid_eth_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp + 1 hours,
                0.01 ether,
                24 hours,
                0
            )
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // listing not configured
        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid{value: 0.1 ether}(address(nft), 2, address(0), 0.1 ether, lid);

        // buy now configured
        vm.prank(ben);
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 24 hours, 0.1 ether));

        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid{value: 0.1 ether}(address(nft), 2, address(0), 0.1 ether, lid);

        // listing not open
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, lid);

        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // bid under reserve price
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid{value: 0.009 ether}(address(nft), 1, address(0), 0.009 ether, lid);

        // funds not attached
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.bid{value: 0 ether}(address(nft), 1, address(0), 0.1 ether, lid);

        // clear mocks
        vm.clearMockedCalls();
    }

    function test_bid_listingChanged() public {
        // ben lists a one hour reserve auction
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0.1 ether, 1 hours, 0)
        );
        uint256 oldId = ah.getListing(address(nft), 1).id;

        // ben relists with a longer duration before chris's bid lands
        ah.delist(address(nft), 1);
        ah.list(
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0.1 ether, 30 days, 0)
        );
        uint256 newId = ah.getListing(address(nft), 1).id;
        vm.stopPrank();
        assertTrue(oldId != newId);

        // bid against the old listing fails
        vm.deal(chris, 0.2 ether);
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, oldId);

        // bid against the new listing succeeds
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, newId);
        assertEq(ah.getListing(address(nft), 1).highestBidder, chris);
    }

    function test_buyNow_listingChanged() public {
        // ben lists for buy now
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 0.1 ether));
        uint256 oldId = ah.getListing(address(nft), 1).id;

        // ben relists at the same price before chris's purchase lands
        ah.delist(address(nft), 1);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 0.1 ether));
        uint256 newId = ah.getListing(address(nft), 1).id;
        vm.stopPrank();
        assertTrue(oldId != newId);

        // purchase against the old listing fails
        vm.deal(chris, 0.1 ether);
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, chris, address(0), 0.1 ether, oldId);

        // purchase against the new listing succeeds
        vm.prank(chris);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, chris, address(0), 0.1 ether, newId);
        assertEq(nft.ownerOf(1), chris);
    }

    function test_getNextBid_reservePrice() public {
        // unlisted token needs a non-zero bid
        assertEq(ah.getNextBid(address(nft), 1), 1);

        // before the first bid, the next bid is the reserve price
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0.5 ether, 1 hours, 0)
        );
        vm.stopPrank();
        assertEq(ah.getNextBid(address(nft), 1), 0.5 ether);

        // after the first bid, the next bid is 5% higher
        lid = ah.getListing(address(nft), 1).id;
        vm.deal(chris, 0.5 ether);
        vm.prank(chris);
        ah.bid{value: 0.5 ether}(address(nft), 1, address(0), 0.5 ether, lid);
        assertEq(ah.getNextBid(address(nft), 1), 0.525 ether);
    }

    function test_getNextBid_roundsUp() public {
        // ben lists a scheduled auction in a coarse currency
        ah.setCurrencyAllowed(address(coin), true);
        coin.transfer(chris, 1000);
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(coin), block.timestamp, 0, 24 hours, 0)
        );
        vm.stopPrank();

        // unbid listing requires a non-zero bid
        assertEq(ah.getNextBid(address(nft), 1), 1);

        // 5% of 39 is 1.95, which rounds up to 2
        lid = ah.getListing(address(nft), 1).id;
        vm.startPrank(chris);
        coin.approve(address(ah), 1000);
        ah.bid(address(nft), 1, address(coin), 39, lid);
        vm.stopPrank();
        assertEq(ah.getNextBid(address(nft), 1), 41);

        // bid of 40 is under 5% and fails
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), 1, address(coin), 40, lid);
    }

    function test_bid_eth_revertingBidder() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // create reverting bidder and bid
        RevertingBidder bidder = new RevertingBidder(address(ah));
        vm.prank(chris);
        bidder.bid{value: 0.01 ether}(address(nft), 1, 0.01 ether);

        // chris bids and has the highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 0.02 ether}(address(nft), 1, address(0), 0.02 ether, lid);

        // ensure auction values are correct
        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.highestBid, 0.02 ether);
        assertEq(l.highestBidder, chris);

        // reverting bidder has refund credited to claim later
        assertEq(address(bidder).balance, 0);
        assertEq(ah.claimableFunds(address(bidder), address(0)), 0.01 ether);

        // bidder can't claim to itself, but can claim to a different address
        vm.expectRevert(TransferHelper.ETHTransferFailed.selector);
        bidder.claimFunds(address(0), address(bidder));
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        bidder.claimFunds(address(0), address(0));
        uint256 prevBalance = anon.balance;
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(address(bidder), address(0), anon, 0.01 ether);
        bidder.claimFunds(address(0), anon);
        assertEq(anon.balance - prevBalance, 0.01 ether);
        assertEq(ah.claimableFunds(address(bidder), address(0)), 0);

        // nothing left to claim
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        bidder.claimFunds(address(0), anon);
    }

    function test_bid_eth_griefingBidder() public {
        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // create griefing bidder and bid
        GriefingBidder bidder = new GriefingBidder(address(ah));
        vm.prank(chris);
        bidder.bid{value: 0.01 ether}(address(nft), 1, 0.01 ether);

        // chris bids and has the highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 0.02 ether}(address(nft), 1, address(0), 0.02 ether, lid);

        // ensure auction values are correct
        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.highestBid, 0.02 ether);
        assertEq(l.highestBidder, chris);

        // griefing bidder has refund credited to claim later
        assertEq(address(bidder).balance, 0);
        assertEq(ah.claimableFunds(address(bidder), address(0)), 0.01 ether);

        // bidder can't claim to itself, but can claim to a different address
        vm.expectRevert(TransferHelper.ETHTransferFailed.selector);
        bidder.claimFunds(address(0), address(bidder));
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        bidder.claimFunds(address(0), address(0));
        uint256 prevBalance = anon.balance;
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(address(bidder), address(0), anon, 0.01 ether);
        bidder.claimFunds(address(0), anon);
        assertEq(anon.balance - prevBalance, 0.01 ether);
        assertEq(ah.claimableFunds(address(bidder), address(0)), 0);

        // nothing left to claim
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        bidder.claimFunds(address(0), anon);
    }

    function test_bid_scheduledAuctionEnded() public {
        // list nft
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // deal 0.1 ether to chris
        vm.deal(chris, 0.1 ether);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // chris bids and it reverts
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.bid{value: 0.02 ether}(address(nft), 1, address(0), 0.02 ether, lid);

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

    function _bid_eth(address nftAddress, uint256 tokenId, address sender, uint256 amount) private {
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
        l.recipient = sender;
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
        ah.bid{value: amount}(address(nft), tokenId, address(0), amount, l.id);

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
            ah.getRoyalty(nftAddress, tokenId, l.highestBid);

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
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_scheduledAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_scheduledAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_scheduledAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuction_primarySale_royaltyLookup(uint64 startDelay, uint256 reservePrice, uint64 duration)
        public
    {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuctionPlusBuyNow_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuctionPlusBuyNow_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_eth(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, bsy, nextBid);

        // ben bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_eth(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 1, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 1, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 1);
    }

    function test_eth_reserveAuctionPlusBuyNow_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    function test_eth_reserveAuctionPlusBuyNow_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                chris,
                address(0),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid{value: reservePrice}(address(nft), 3, address(0), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_eth(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, bsy, nextBid);

        // chris bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_eth(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_eth(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid{value: 700 ether}(address(nft), 3, address(0), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid{value: 900 ether}(address(nft), 3, address(0), 900 ether, lid);

        // settle the auction
        _settle_auction(address(nft), 3);
    }

    /////////////////////////////////////////////////////////////////////
    // TEST BID ERC-20
    /////////////////////////////////////////////////////////////////////

    function test_first_bid_erc20_errors() public {
        // list
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(coin),
                block.timestamp + 1 hours,
                0.01 ether,
                24 hours,
                0
            )
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.bid(address(nft), 1, address(coin), 0.1 ether, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // listing not configured
        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid(address(nft), 2, address(coin), 0.1 ether, lid);

        // buy now configured
        vm.prank(ben);
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 24 hours, 0.1 ether));

        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid(address(nft), 2, address(coin), 0.1 ether, lid);

        // listing not open
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
        ah.bid(address(nft), 1, address(coin), 0.1 ether, lid);

        vm.warp(block.timestamp + 1 hours + 1 seconds);

        // bid under reserve price
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), 1, address(coin), 0.009 ether, lid);

        // funds attached
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector); // coin reverts due to not being approved
        ah.bid{value: 0.1 ether}(address(nft), 1, address(coin), 0.1 ether, lid);

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.bid(address(nft), 1, address(coin), 0.1 ether, lid);

        // not enought coin supply
        vm.startPrank(chris);
        coin.approve(address(ah), 10000000 ether);
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 10000 ether, 10000000 ether)
        ); // coin reverts due to insufficient balance
        ah.bid(address(nft), 1, address(coin), 10000000 ether, lid);

        // clear mocks
        vm.clearMockedCalls();
    }

    function _bid_erc20(address nftAddress, uint256 tokenId, address sender, uint256 amount) private {
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
        l.recipient = sender;
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
        ah.bid(address(nft), tokenId, address(coin), amount, l.id);

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
            ah.getRoyalty(nftAddress, tokenId, l.highestBid);

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
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_scheduledAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_scheduledAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_scheduledAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuction_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuction_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuction_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuction_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuctionPlusBuyNow_primarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuctionPlusBuyNow_primarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 1, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // chris kicks off auction
        _bid_erc20(address(nft), 1, chris, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, bsy, nextBid);

        // ben  bids
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, ben, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 1);
        _bid_erc20(address(nft), 1, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 1, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 1, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 1);
    }

    function test_erc20_reserveAuctionPlusBuyNow_secondarySale_royaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    function test_erc20_reserveAuctionPlusBuyNow_secondarySale_noRoyaltyLookup(
        uint64 startDelay,
        uint256 reservePrice,
        uint64 duration
    ) public {
        // limit fuzz variables
        vm.assume(duration > 0); // makes sure that auction can always be kicked off
        if (reservePrice > 500 ether) {
            reservePrice %= 500 ether;
        }
        if (reservePrice == 0) reservePrice = 1; // first bid must be non-zero

        if (duration > 30 days) {
            duration = duration % 30 days + 1;
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                chris,
                address(coin),
                block.timestamp + startDelay,
                reservePrice,
                duration,
                0
            )
        );
        vm.stopPrank();

        // try bidding before the auction starts
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(ben);
            vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
            ah.bid(address(nft), 3, address(coin), reservePrice, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // ben kicks off auction
        _bid_erc20(address(nft), 3, ben, reservePrice);

        // bsy bids
        uint256 nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, bsy, nextBid);

        // chris  bids
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, chris, nextBid);

        // anon bids for david
        nextBid = ah.getNextBid(address(nft), 3);
        _bid_erc20(address(nft), 3, anon, nextBid);

        // bsy bids a crazy amount to win at the last mint
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration - 10);
        _bid_erc20(address(nft), 3, bsy, 777 ether);

        // bid under highest bid
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 700 ether, lid);

        // no one can beat the bid, go to end of auction
        l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // try bidding again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        vm.prank(david);
        ah.bid(address(nft), 3, address(coin), 900 ether, lid);

        // settle the auction
        _settle_auction_erc20(address(nft), 3);
    }

    /////////////////////////////////////////////////////////////////////
    // TEST SETTLE AUCTION
    /////////////////////////////////////////////////////////////////////

    function test_settleAuction_errors() public {
        // list nfts
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.SCHEDULED_AUCTION,
                ben,
                address(0),
                block.timestamp + 24 hours,
                0.01 ether,
                24 hours,
                0
            )
        );
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0));
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
        lid = ah.getListing(address(nft), 1).id;
        vm.warp(block.timestamp + 24 hours);
        vm.deal(chris, 0.1 ether);
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, lid);

        // auction not ended
        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), 1);

        vm.warp(block.timestamp + 24 hours);

        vm.expectRevert(TLAuctionHouse.AuctionNotEnded.selector);
        ah.settleAuction(address(nft), 1);
    }

    /////////////////////////////////////////////////////////////////////
    // TEST SETTLE UP FUNCTION
    /////////////////////////////////////////////////////////////////////

    function test_settleUp_royaltyLookupReverts() public {
        // mock royalty lookup
        vm.mockCallRevert(address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyalty.selector), "revert");
        vm.mockCallRevert(address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyaltyView.selector), "revert");

        // ensure 0 royalties returned
        (address payable[] memory r,) = ah.getRoyalty(address(nft), 3, 10_000);
        assertEq(r.length, 0);

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        lid = ah.getListing(address(nft), 3).id;
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, address(0), 0.1 ether, lid);

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
        vm.mockCall(address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyalty.selector), abi.encode(r, amts));

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        lid = ah.getListing(address(nft), 3).id;
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, address(0), 0.1 ether, lid);

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
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        lid = ah.getListing(address(nft), 3).id;
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, address(0), 0.1 ether, lid);

        // warp to end of auction
        Listing memory l = ah.getListing(address(nft), 3);
        vm.warp(l.startTime + l.duration + 1);

        // get previous balances
        uint256 ahPrevBalance = address(ah).balance;
        uint256 chrisPrevBalance = chris.balance;
        uint256 benPrevBalance = ben.balance;

        // set sanctions oracle
        ah.setSanctionsOracle(oracle);

        // mock sanctions call to return true for the royalty recipient only
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );

        // settle the auction
        ah.settleAuction(address(nft), 3);

        // check balances
        assertEq(ahPrevBalance - address(ah).balance, 0.09 ether); // frozen royalty stays in escrow
        assertEq(ben.balance - benPrevBalance, 0); // royalties not paid due to sanctions
        assertEq(ah.claimableFunds(ben, address(0)), 0.01 ether); // but frozen for the royalty recipient
        assertEq(chris.balance - chrisPrevBalance, 0.09 ether);
        assertEq(nft.ownerOf(3), david);

        vm.clearMockedCalls();
    }

    function test_settleUp_bigRoyalties() public {
        // mock royalty lookup
        address payable[] memory r = new address payable[](1);
        r[0] = payable(address(1));
        uint256[] memory amts = new uint256[](1);
        amts[0] = 1 ether;
        vm.mockCall(address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyalty.selector), abi.encode(r, amts));

        // list nft
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        // set protocol fee to zero for the auction
        ah.removeProtocolFee(address(nft), 3);

        // deal and bid
        lid = ah.getListing(address(nft), 3).id;
        vm.deal(david, 0.1 ether);
        vm.prank(david);
        ah.bid{value: 0.1 ether}(address(nft), 3, address(0), 0.1 ether, lid);

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
        assertEq(ben.balance - benPrevBalance, 0);
        assertEq(address(1).balance, 0.01 ether); // royalty clamped to 10% of the sale
        assertEq(chris.balance - chrisPrevBalance, 0.09 ether);

        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    // TEST BUY NOW ETH
    /////////////////////////////////////////////////////////////////////

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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, address(0), address(0), type(uint256).max, lid);

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, anon, address(0), type(uint256).max, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(false)
        );

        // not configured listing
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);

        // configured as scheduled auction
        vm.prank(chris);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(chris);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(0),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );

        lid = ah.getListing(address(nft), 3).id;
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 3, ben, address(0), type(uint256).max, lid);

        // configured as reserve auction
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0.01 ether, 24 hours, 0
            )
        );

        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 2, chris, address(0), type(uint256).max, lid);

        vm.prank(ben);
        ah.delist(address(nft), 2);

        // list nft 1 as reserve + buy now
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(0),
                block.timestamp + 24 hours,
                0.01 ether,
                24 hours,
                0.1 ether
            )
        );

        // list nft 2 as buy now
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft),
                2,
                ListingType.BUY_NOW,
                ben,
                address(0),
                block.timestamp + 24 hours,
                0,
                24 hours,
                0.1 ether
            )
        );

        // trying to buy too soon
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, chris, address(0), type(uint256).max, lid);

        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.1 ether}(address(nft), 2, chris, address(0), type(uint256).max, lid);

        // warp
        vm.warp(block.timestamp + 24 hours);

        // not enough eth attached
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 1, chris, address(0), type(uint256).max, lid);

        // too much eth attached
        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 1 ether}(address(nft), 2, chris, address(0), type(uint256).max, lid);

        // auction in progress
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 0.1 ether}(address(nft), 1, address(0), 0.1 ether, lid);

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(anon);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.buyNow{value: 0.1 ether}(address(nft), 1, anon, address(0), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(0),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(0),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(0),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, buyNowPrice);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(0), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(0),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(0), type(uint256).max, lid);
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
        ah.list(
            _cfg(
                address(nft), 1, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);
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
        ah.list(
            _cfg(
                address(nft), 1, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 1, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(0), type(uint256).max, lid);
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
        ah.list(
            _cfg(
                address(nft), 3, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, buyNowPrice);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(0), type(uint256).max, lid);
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
        ah.list(
            _cfg(
                address(nft), 3, ListingType.BUY_NOW, anon, address(0), block.timestamp + startDelay, 0, 0, buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow{value: buyNowPrice}(address(nft), 3, recipient, address(0), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(0), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(0), type(uint256).max, lid);
    }

    /////////////////////////////////////////////////////////////////////
    // TEST BUY NOW ERC-20
    /////////////////////////////////////////////////////////////////////

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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, chris), abi.encode(false)
        );

        // zero address recpient
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, address(0), address(coin), type(uint256).max, lid);

        // sanctioned recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(true)
        );
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow(address(nft), 1, anon, address(coin), type(uint256).max, lid);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, anon), abi.encode(false)
        );

        // not configured listing
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);

        // configured as scheduled auction
        vm.prank(chris);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(chris);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.SCHEDULED_AUCTION,
                chris,
                address(coin),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );

        lid = ah.getListing(address(nft), 3).id;
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 3, ben, address(coin), type(uint256).max, lid);

        // configured as reserve auction
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft),
                2,
                ListingType.RESERVE_AUCTION,
                ben,
                address(coin),
                block.timestamp,
                0.01 ether,
                24 hours,
                0
            )
        );

        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.buyNow(address(nft), 2, chris, address(coin), type(uint256).max, lid);

        vm.prank(ben);
        ah.delist(address(nft), 2);

        // list nft 1 as reserve + buy now
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(coin),
                block.timestamp + 24 hours,
                0.01 ether,
                24 hours,
                0.1 ether
            )
        );

        // list nft 2 as buy now
        vm.prank(ben);
        ah.list(
            _cfg(
                address(nft),
                2,
                ListingType.BUY_NOW,
                ben,
                address(coin),
                block.timestamp + 24 hours,
                0,
                24 hours,
                0.1 ether
            )
        );

        // trying to buy too soon
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);

        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 2, chris, address(coin), type(uint256).max, lid);

        // warp
        vm.warp(block.timestamp + 24 hours);

        // eth attached
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 1, chris, address(coin), type(uint256).max, lid);

        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        vm.prank(chris);
        ah.buyNow{value: 0.01 ether}(address(nft), 2, chris, address(coin), type(uint256).max, lid);

        // not enough coin allowance
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);

        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(ah), 0, 0.1 ether)
        ); // coin reverts due to not being approved
        ah.buyNow(address(nft), 2, chris, address(coin), type(uint256).max, lid);

        // not enought coin supply
        vm.startPrank(chris);
        coin.approve(address(ah), 10000 ether);
        coin.transfer(address(this), 10000 ether);
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether)); // coin reverts due to insufficient balance
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether)); // coin reverts due to insufficient balance
        ah.buyNow(address(nft), 2, chris, address(coin), type(uint256).max, lid);
        vm.stopPrank();

        coin.transfer(chris, 10000 ether);

        // auction in progress
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid(address(nft), 1, address(coin), 0.1 ether, lid);

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(anon);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.buyNow(address(nft), 1, anon, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(coin), 0, lid);

        // try buying
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(coin), 0, lid);

        // try buying
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, buyNowPrice);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(coin), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(coin), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(coin), 0, lid);

        // try buying
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                1,
                ListingType.BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // buyer approves auction house
        vm.prank(buyer);
        coin.approve(address(ah), 1000 ether);

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 1).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 1, recipient, l);
        ah.buyNow(address(nft), 1, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.bid(address(nft), 1, address(coin), 0, lid);

        // try buying
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(chris);
        ah.buyNow(address(nft), 1, chris, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);

        // ensure funds transfer properly
        uint256 protocolFee = buyNowPrice * ah.protocolFeeBps() / ah.BASIS();
        uint256 remainingBalance = buyNowPrice - protocolFee;
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, buyNowPrice);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(coin), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(coin), type(uint256).max, lid);
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
            _cfg(
                address(nft),
                3,
                ListingType.BUY_NOW,
                anon,
                address(coin),
                block.timestamp + startDelay,
                0,
                0,
                buyNowPrice
            )
        );
        vm.stopPrank();

        // test buying before start time
        if (startDelay > 0) {
            lid = ah.getListing(address(nft), 3).id;
            vm.prank(buyer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);
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
        lid = ah.getListing(address(nft), 3).id;
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(buyer, address(nft), 3, recipient, l);
        ah.buyNow(address(nft), 3, recipient, address(coin), type(uint256).max, lid);

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
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.bid(address(nft), 3, address(coin), 0, lid);

        // try buying again
        lid = ah.getListing(address(nft), 3).id;
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        vm.prank(ben);
        ah.buyNow(address(nft), 3, ben, address(coin), type(uint256).max, lid);
    }

    /////////////////////////////////////////////////////////////////////
    // SECURITY HARDENING
    /////////////////////////////////////////////////////////////////////

    /// @dev lists `tokenId` as a scheduled ETH auction, bids `amount` from `bidder`, and warps to the end
    function _listBidAndEnd(
        address nftAddress,
        uint256 tokenId,
        address seller,
        address payoutReceiver,
        address bidder,
        uint256 amount
    ) private {
        vm.startPrank(seller);
        BadERC721(nftAddress).setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                nftAddress,
                tokenId,
                ListingType.SCHEDULED_AUCTION,
                payoutReceiver,
                address(0),
                block.timestamp,
                0,
                24 hours,
                0
            )
        );
        vm.stopPrank();

        lid = ah.getListing(nftAddress, tokenId).id;
        vm.deal(bidder, amount);
        vm.prank(bidder);
        ah.bid{value: amount}(nftAddress, tokenId, address(0), amount, lid);

        Listing memory l = ah.getListing(nftAddress, tokenId);
        vm.warp(l.startTime + l.duration + 1);
    }

    function _sanction(address account) private {
        ah.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, account), abi.encode(true)
        );
    }

    function _mockRoyalties(address payable[] memory recipients, uint256[] memory amounts) private {
        vm.mockCall(
            address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyalty.selector), abi.encode(recipients, amounts)
        );
    }

    function test_list_alreadyListed() public {
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        _listBidAndEnd(address(bad), 1, ben, ben, chris, 1 ether);

        // nft lies about ownership so the seller appears to own it again
        bad.setFakeOwner(ben);
        bad.setMode(BadERC721.Mode.LIE_OWNER_OF);

        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.AlreadyListed.selector);
        ah.list(_cfg(address(bad), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 0.1 ether));

        // bid is still intact
        Listing memory l = ah.getListing(address(bad), 1);
        assertEq(l.highestBidder, chris);
        assertEq(l.highestBid, 1 ether);
    }

    function test_list_invalidPayoutReceiverAndDuration() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);

        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, address(0), address(0), block.timestamp, 0, 0, 1 ether));

        uint256 tooLong = ah.MAX_AUCTION_DURATION() + 1;
        vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), block.timestamp, 0, tooLong, 0));
        vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, tooLong, 0));
        vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        ah.list(
            _cfg(
                address(nft),
                1,
                ListingType.RESERVE_AUCTION_PLUS_BUY_NOW,
                ben,
                address(0),
                block.timestamp,
                0,
                tooLong,
                1
            )
        );

        // buy now ignores duration
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, tooLong, 1 ether));
        assertEq(ah.getListing(address(nft), 1).duration, 0);
        vm.stopPrank();
    }

    function test_bid_zeroFirstBid() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        vm.stopPrank();

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid(address(nft), 1, address(0), 0, lid);

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 1}(address(nft), 1, address(0), 1, lid);
        assertEq(ah.getListing(address(nft), 1).highestBid, 1);
    }

    function test_bid_currencyMismatch() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        ah.list(_cfg(address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(coin), block.timestamp, 0, 24 hours, 0));
        vm.stopPrank();

        vm.startPrank(chris);
        coin.approve(address(ah), type(uint256).max);
        lid = ah.getListing(address(nft), 1).id;
        vm.expectRevert(TLAuctionHouse.CurrencyMismatch.selector);
        ah.bid(address(nft), 1, address(coin), 1 ether, lid);
        lid = ah.getListing(address(nft), 2).id;
        vm.expectRevert(TLAuctionHouse.CurrencyMismatch.selector);
        ah.bid{value: 1 ether}(address(nft), 2, address(0), 1 ether, lid);
        vm.stopPrank();
    }

    function test_buyNow_frontRunRelist() public {
        // seller lists for 1 coin
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(coin), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        // buyer has a large outstanding approval
        vm.prank(chris);
        coin.approve(address(ah), type(uint256).max);

        // seller front-runs by relisting at a higher price, and then in a different currency
        vm.startPrank(ben);
        ah.delist(address(nft), 1);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(coin), block.timestamp, 0, 0, 100 ether));
        vm.stopPrank();

        uint256 chrisPrevBalance = coin.balanceOf(chris);
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.PriceTooHigh.selector);
        ah.buyNow(address(nft), 1, chris, address(coin), 1 ether, lid);

        vm.startPrank(ben);
        ah.delist(address(nft), 1);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CurrencyMismatch.selector);
        ah.buyNow(address(nft), 1, chris, address(coin), 1 ether, lid);

        assertEq(coin.balanceOf(chris), chrisPrevBalance);
    }

    function test_settleAuction_expensiveTransfer() public {
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        _listBidAndEnd(address(bad), 1, ben, anon, chris, 1 ether);

        // nfts with heavy transfer hooks get all the gas they need
        bad.setMode(BadERC721.Mode.EXPENSIVE_TRANSFER);
        uint256 anonPrevBalance = anon.balance;
        ah.settleAuction(address(bad), 1);
        assertEq(bad.ownerOf(1), chris);
        assertEq(anon.balance - anonPrevBalance, 0.99 ether);
        assertEq(ah.claimableFunds(chris, address(0)), 0);
    }

    function test_settleAuction_gasBombLookups() public {
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        _listBidAndEnd(address(bad), 1, ben, anon, chris, 1 ether);
        Listing memory l = ah.getListing(address(bad), 1);

        // both the creator lookup (`owner`) and royalty lookup (`royaltyInfo`) burn all gas given to them, so the
        // nft contract blocks settlement, just as it could by blocking transfers
        bad.setContractOwnerMode(BadERC721.ContractOwnerMode.BURN_GAS);
        vm.expectRevert();
        ah.settleAuction{gas: 10_000_000}(address(bad), 1);

        // the auction unwinds after the grace period without calling the nft
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);
        vm.prank(chris);
        ah.cancelUnsettledAuction{gas: 300_000}(address(bad), 1);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        assertEq(ah.claimableNft(address(bad), 1), ben);
    }

    function test_settleAuction_sanctionedPayoutReceiver() public {
        _listBidAndEnd(address(nft), 1, ben, anon, chris, 1 ether);
        _sanction(anon);

        uint256 anonPrevBalance = anon.balance;
        ah.settleAuction(address(nft), 1);

        // sale completes, but proceeds are frozen
        assertEq(nft.ownerOf(1), chris);
        assertEq(anon.balance, anonPrevBalance);
        assertEq(ah.claimableFunds(anon, address(0)), 0.99 ether);
        vm.prank(anon);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.claimFunds(address(0), anon);
        vm.clearMockedCalls();
    }

    function test_bid_previousBidderSanctioned() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        vm.stopPrank();

        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);

        _sanction(chris);
        uint256 chrisPrevBalance = chris.balance;
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(david);
        ah.bid{value: 2 ether}(address(nft), 1, address(0), 2 ether, lid);

        assertEq(chris.balance, chrisPrevBalance);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        vm.clearMockedCalls();
    }

    function test_settleUp_creatorLookupUnsetOrMalformed() public {
        // creator lookup unset: treated as secondary sale, royalties paid via ERC-2981 (10% to ben)
        ah.setCreatorLookup(address(0));
        _listBidAndEnd(address(nft), 1, ben, anon, chris, 1 ether);
        uint256 benPrevBalance = ben.balance;
        uint256 anonPrevBalance = anon.balance;
        ah.settleAuction(address(nft), 1);
        assertEq(nft.ownerOf(1), chris);
        assertEq(ben.balance - benPrevBalance, 0.1 ether);
        assertEq(anon.balance - anonPrevBalance, 0.89 ether);
        ah.setCreatorLookup(address(cl));

        // nft contract returns malformed `owner()` data
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        _listBidAndEnd(address(bad), 1, ben, anon, chris, 1 ether);
        bad.setContractOwnerMode(BadERC721.ContractOwnerMode.MALFORMED);

        anonPrevBalance = anon.balance;
        ah.settleAuction(address(bad), 1);
        assertEq(bad.ownerOf(1), chris);
        assertEq(anon.balance - anonPrevBalance, 0.99 ether); // no ERC-2981 on the bad nft
    }

    function test_getRoyalty_cappedLikeSettlement() public {
        // 12 recipients asking for 5% each, with a zero address in the mix
        address payable[] memory r = new address payable[](12);
        uint256[] memory amts = new uint256[](12);
        for (uint256 i = 0; i < 12; ++i) {
            r[i] = payable(address(uint160(i + 1)));
            amts[i] = 0.05 ether;
        }
        r[1] = payable(address(0));
        vm.mockCall(address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyaltyView.selector), abi.encode(r, amts));

        // view matches what settlement pays: first 10 recipients, zero address skipped, 10% total
        (address payable[] memory recipients, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, 1 ether);
        assertEq(recipients.length, 10);
        assertEq(amounts[0], 0.05 ether);
        assertEq(amounts[1], 0);
        assertEq(amounts[2], 0.05 ether);
        for (uint256 i = 3; i < 10; ++i) {
            assertEq(amounts[i], 0);
        }

        // mismatched array lengths return nothing
        vm.mockCall(
            address(rl), abi.encodeWithSelector(RoyaltyLookup.getRoyaltyView.selector), abi.encode(r, new uint256[](1))
        );
        (recipients, amounts) = ah.getRoyalty(address(nft), 3, 1 ether);
        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);
        vm.clearMockedCalls();
    }

    function test_settleUp_zeroAddressRoyalty() public {
        address payable[] memory r = new address payable[](2);
        r[0] = payable(address(0));
        r[1] = payable(address(1));
        uint256[] memory amts = new uint256[](2);
        amts[0] = 0.05 ether;
        amts[1] = 0.05 ether;
        _mockRoyalties(r, amts);

        _listBidAndEnd(address(nft), 3, chris, chris, david, 1 ether);
        uint256 chrisPrevBalance = chris.balance;
        ah.settleAuction(address(nft), 3);

        // zero address share stays with the seller instead of getting stuck
        assertEq(address(1).balance, 0.05 ether);
        assertEq(chris.balance - chrisPrevBalance, 0.94 ether);
        assertEq(address(ah).balance, 0);
        vm.clearMockedCalls();
    }

    function test_settleUp_royaltyCaps() public {
        // recipient cap
        uint256 n = ah.MAX_ROYALTY_RECIPIENTS() + 1;
        address payable[] memory r = new address payable[](n);
        uint256[] memory amts = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            r[i] = payable(address(uint160(0x1000 + i)));
            amts[i] = 0.005 ether;
        }
        _mockRoyalties(r, amts);

        _listBidAndEnd(address(nft), 3, chris, chris, david, 1 ether);
        uint256 chrisPrevBalance = chris.balance;
        ah.settleAuction(address(nft), 3);
        assertEq(r[n - 2].balance, 0.005 ether);
        assertEq(r[n - 1].balance, 0);
        assertEq(chris.balance - chrisPrevBalance, 0.99 ether - 0.05 ether);
        vm.clearMockedCalls();

        // total royalty cap (10% of the 1 ether sale), later recipients are clamped to what's left
        r = new address payable[](2);
        r[0] = payable(address(0x2000));
        r[1] = payable(address(0x2001));
        amts = new uint256[](2);
        amts[0] = 0.08 ether;
        amts[1] = 0.05 ether;
        _mockRoyalties(r, amts);

        _listBidAndEnd(address(nft), 3, david, david, chris, 1 ether);
        uint256 davidPrevBalance = david.balance;
        ah.settleAuction(address(nft), 3);
        assertEq(r[0].balance, 0.08 ether);
        assertEq(r[1].balance, 0.02 ether);
        assertEq(david.balance - davidPrevBalance, 0.89 ether);
        vm.clearMockedCalls();
    }

    function test_bid_feeOnTransferCurrency() public {
        // a fee-on-transfer currency is allowlisted by mistake
        FeeOnTransferERC20 token = new FeeOnTransferERC20(chris);
        ah.setCurrencyAllowed(address(token), true);
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(token), block.timestamp, 1 ether, 1 hours, 0
            )
        );
        vm.stopPrank();

        // escrow receives less than the bid, so the bid reverts rather than leaving the auction underfunded
        lid = ah.getListing(address(nft), 1).id;
        vm.startPrank(chris);
        token.approve(address(ah), 1 ether);
        vm.expectRevert(TransferHelper.InsufficentERC20Transfer.selector);
        ah.bid(address(nft), 1, address(token), 1 ether, lid);
        vm.stopPrank();
        assertEq(token.balanceOf(address(ah)), 0);
    }

    function test_payout_erc20Blocklist() public {
        BlocklistERC20 token = new BlocklistERC20(address(this));
        ah.setCurrencyAllowed(address(token), true);
        token.transfer(chris, 10 ether);

        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, anon, address(token), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        // payout receiver gets blocked by the token
        token.setBlocked(anon, true);

        vm.startPrank(chris);
        token.approve(address(ah), 1 ether);
        lid = ah.getListing(address(nft), 1).id;
        vm.expectEmit(true, true, true, true);
        emit FundsCredited(anon, address(token), 0.99 ether);
        ah.buyNow(address(nft), 1, chris, address(token), 1 ether, lid);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), chris);
        assertEq(token.balanceOf(tl), 0.01 ether);
        assertEq(ah.claimableFunds(anon, address(token)), 0.99 ether);

        // can't claim to the blocked address, but can redirect
        vm.startPrank(anon);
        vm.expectRevert("blocked");
        ah.claimFunds(address(token), anon);
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(anon, address(token), bsy, 0.99 ether);
        ah.claimFunds(address(token), bsy);
        vm.stopPrank();
        assertEq(token.balanceOf(bsy), 0.99 ether);
        assertEq(token.balanceOf(address(ah)), 0);
    }

    function test_claim_whilePaused() public {
        RevertingBidder bidder = new RevertingBidder(address(ah));
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        vm.stopPrank();
        bidder.bid{value: 1 ether}(address(nft), 1, 1 ether);
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 2 ether}(address(nft), 1, address(0), 2 ether, lid);

        ah.pause(true);
        uint256 anonPrevBalance = anon.balance;
        bidder.claimFunds(address(0), anon);
        assertEq(anon.balance - anonPrevBalance, 1 ether);
    }

    function test_removeProtocolFee_event() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeRemoved(address(nft), 1);
        ah.removeProtocolFee(address(nft), 1);
    }

    function test_currencyAllowlist() public {
        MockERC20 other = new MockERC20(address(this));

        // owner only
        vm.prank(anon);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, anon));
        ah.setCurrencyAllowed(address(other), true);

        // non-allowlisted currency can't be listed
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(other), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        // eth is always allowed, even if explicitly removed
        ah.setCurrencyAllowed(address(0), false);
        vm.prank(ben);
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));

        // allowlisting enables listing
        vm.expectEmit(true, true, true, true);
        emit CurrencyAllowlist.CurrencyAllowlistUpdated(address(other), true);
        ah.setCurrencyAllowed(address(other), true);
        assertTrue(ah.allowedCurrencies(address(other)));
        vm.prank(ben);
        ah.list(
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(other), block.timestamp, 0, 24 hours, 0)
        );

        // removing a currency doesn't affect live listings
        other.transfer(chris, 10 ether);
        vm.startPrank(chris);
        other.approve(address(ah), 1 ether);
        lid = ah.getListing(address(nft), 1).id;
        ah.bid(address(nft), 1, address(other), 1 ether, lid);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit CurrencyAllowlist.CurrencyAllowlistUpdated(address(other), false);
        ah.setCurrencyAllowed(address(other), false);

        vm.warp(block.timestamp + 25 hours);
        ah.settleAuction(address(nft), 1);
        assertEq(nft.ownerOf(1), chris);
        assertEq(other.balanceOf(ben), 0.99 ether);
    }

    function test_sanctionedSeller_blocksDelistBuyNowAndSettle() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        _sanction(ben);

        // seller can't pull their escrowed nft back out
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.delist(address(nft), 1);

        // buyers can't buy from the sanctioned seller
        lid = ah.getListing(address(nft), 2).id;
        vm.deal(chris, 2 ether);
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.buyNow{value: 1 ether}(address(nft), 2, chris, address(0), 1 ether, lid);

        // bids are accepted, but the auction can't settle with the sanctioned seller
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + 1);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.settleAuction(address(nft), 1);

        // bidder recovers their funds after the grace period, and the nft is frozen for the seller
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);
        vm.prank(chris);
        ah.cancelUnsettledAuction(address(nft), 1);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        assertEq(ah.claimableNft(address(nft), 1), ben);

        vm.clearMockedCalls();
    }

    function test_buyNow_nftTransferFails() public {
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        bad.mint(ben, 2);
        vm.startPrank(ben);
        bad.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(bad), 1, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        ah.list(_cfg(address(bad), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        uint256 chrisPrevBalance = chris.balance;

        // reverting transfer
        bad.setMode(BadERC721.Mode.REVERT_TRANSFER);
        lid = ah.getListing(address(bad), 1).id;
        vm.prank(chris);
        vm.expectRevert("no transfers");
        ah.buyNow{value: 1 ether}(address(bad), 1, chris, address(0), 1 ether, lid);

        // transfer that doesn't actually move the nft
        bad.setMode(BadERC721.Mode.NOOP_TRANSFER);
        lid = ah.getListing(address(bad), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NftTransferFailed.selector);
        ah.buyNow{value: 1 ether}(address(bad), 2, chris, address(0), 1 ether, lid);

        assertEq(chris.balance, chrisPrevBalance);
    }

    function test_cancelUnsettledAuction_nftFailsToTransfer() public {
        BadERC721.Mode[3] memory modes =
            [BadERC721.Mode.REVERT_TRANSFER, BadERC721.Mode.NOOP_TRANSFER, BadERC721.Mode.BURN_GAS_TRANSFER];

        for (uint256 i = 0; i < modes.length; ++i) {
            BadERC721 bad = new BadERC721(ben);
            bad.mint(ben, 1);
            _listBidAndEnd(address(bad), 1, ben, anon, chris, 1 ether);
            Listing memory l = ah.getListing(address(bad), 1);

            // settlement can't complete
            bad.setMode(modes[i]);
            vm.expectRevert();
            ah.settleAuction{gas: 10_000_000}(address(bad), 1);

            // can't cancel until the grace period is over
            vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD());
            vm.prank(chris);
            vm.expectRevert(TLAuctionHouse.SettlementGracePeriodNotOver.selector);
            ah.cancelUnsettledAuction(address(bad), 1);

            // bidder cancels, without any calls to the nft
            vm.warp(block.timestamp + 1);
            uint256 anonPrevBalance = anon.balance;
            vm.expectEmit(true, true, true, true);
            emit FundsCredited(chris, address(0), 1 ether);
            vm.expectEmit(true, true, true, true);
            emit NftCredited(ben, address(bad), 1);
            vm.expectEmit(true, true, true, true);
            emit ListingCanceled(chris, address(bad), 1, l);
            vm.prank(chris);
            ah.cancelUnsettledAuction{gas: 300_000}(address(bad), 1);

            // seller and protocol not paid, bidder refund is claimableFunds, nft held for seller
            assertEq(anon.balance, anonPrevBalance);
            assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
            assertEq(ah.claimableNft(address(bad), 1), ben);
            assertEq(uint8(ah.getListing(address(bad), 1).type_), uint8(ListingType.NOT_CONFIGURED));

            uint256 chrisPrevBalance = chris.balance;
            vm.prank(chris);
            ah.claimFunds(address(0), chris);
            assertEq(chris.balance - chrisPrevBalance, 1 ether);
            assertEq(address(ah).balance, 0);
        }
    }

    function test_cancelUnsettledAuction_errors() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), block.timestamp, 0, 0, 1 ether));
        vm.stopPrank();

        // not configured
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.cancelUnsettledAuction(address(nft), 3);

        // buy now
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.cancelUnsettledAuction(address(nft), 2);

        // no bids
        vm.prank(ben);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), block.timestamp, 0, 24 hours, 0));
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.AuctionNotStarted.selector);
        ah.cancelUnsettledAuction(address(nft), 1);

        // bid and end, then wait out the grace period
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), 1);
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);

        // only the seller or highest bidder
        vm.prank(anon);
        vm.expectRevert(TLAuctionHouse.NotSellerOrBidder.selector);
        ah.cancelUnsettledAuction(address(nft), 1);

        // seller can cancel, even while paused
        ah.pause(true);
        vm.prank(ben);
        ah.cancelUnsettledAuction(address(nft), 1);
        ah.pause(false);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        assertEq(ah.claimableNft(address(nft), 1), ben);

        // auction can no longer be settled or canceled
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.settleAuction(address(nft), 1);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.cancelUnsettledAuction(address(nft), 1);

        // seller reclaims the nft
        vm.prank(ben);
        ah.claimNft(address(nft), 1, ben);
        assertEq(nft.ownerOf(1), ben);
    }

    function test_settleAuction_sanctionedBidder() public {
        // sanctioned bidder: settlement reverts, seller cancels after the grace period and the refund is frozen
        _listBidAndEnd(address(nft), 1, ben, ben, chris, 1 ether);
        _sanction(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.settleAuction(address(nft), 1);

        vm.warp(block.timestamp + ah.SETTLEMENT_GRACE_PERIOD());
        vm.prank(ben);
        ah.cancelUnsettledAuction(address(nft), 1);
        vm.prank(ben);
        ah.claimNft(address(nft), 1, ben);
        assertEq(nft.ownerOf(1), ben);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.claimFunds(address(0), david);
        vm.clearMockedCalls();
    }

    function test_settleAuction_sanctionedSeller() public {
        _listBidAndEnd(address(nft), 1, ben, anon, chris, 1 ether);
        _sanction(ben);

        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.settleAuction(address(nft), 1);

        // bidder cancels after the grace period, and the nft is frozen in escrow for the seller
        vm.warp(block.timestamp + ah.SETTLEMENT_GRACE_PERIOD());
        uint256 anonPrevBalance = anon.balance;
        vm.prank(chris);
        ah.cancelUnsettledAuction(address(nft), 1);
        assertEq(anon.balance, anonPrevBalance);
        assertEq(ah.claimableFunds(chris, address(0)), 1 ether);
        assertEq(nft.ownerOf(1), address(ah));
        assertEq(ah.claimableNft(address(nft), 1), ben);

        // seller can't claim while sanctioned
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.claimNft(address(nft), 1, ben);

        // once no longer sanctioned, the seller can claim, but no one else can
        vm.clearMockedCalls();
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        ah.claimNft(address(nft), 1, chris);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.claimNft(address(nft), 1, address(0));

        // claims can't be sent to a sanctioned address
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, david), abi.encode(true)
        );
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.claimNft(address(nft), 1, david);
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.claimFunds(address(0), david);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, david), abi.encode(false)
        );

        vm.prank(ben);
        vm.expectEmit(true, true, true, true);
        emit NftClaimed(ben, address(nft), 1, david);
        ah.claimNft(address(nft), 1, david);
        assertEq(nft.ownerOf(1), david);
        assertEq(ah.claimableNft(address(nft), 1), address(0));

        // bidder reclaims their funds
        uint256 chrisPrevBalance = chris.balance;
        vm.prank(chris);
        ah.claimFunds(address(0), chris);
        assertEq(chris.balance - chrisPrevBalance, 1 ether);
        vm.clearMockedCalls();
    }

    function test_claimNft_brokenNft() public {
        BadERC721 bad = new BadERC721(ben);
        bad.mint(ben, 1);
        _listBidAndEnd(address(bad), 1, ben, ben, chris, 1 ether);

        // nft can't be delivered, so the auction is canceled after the grace period and the nft held for the seller
        bad.setMode(BadERC721.Mode.REVERT_TRANSFER);
        vm.expectRevert("no transfers");
        ah.settleAuction(address(bad), 1);
        vm.warp(block.timestamp + ah.SETTLEMENT_GRACE_PERIOD());
        vm.prank(chris);
        ah.cancelUnsettledAuction(address(bad), 1);
        assertEq(ah.claimableNft(address(bad), 1), ben);

        // claiming fails while the nft is broken, but the claim is kept
        vm.prank(ben);
        vm.expectRevert("no transfers");
        ah.claimNft(address(bad), 1, ben);
        assertEq(ah.claimableNft(address(bad), 1), ben);

        // once transfers work again, the seller can claim
        bad.setMode(BadERC721.Mode.NORMAL);
        vm.prank(ben);
        ah.claimNft(address(bad), 1, ben);
        assertEq(bad.ownerOf(1), ben);
    }

    /////////////////////////////////////////////////////////////////////
    // PRIVATE SALE
    /////////////////////////////////////////////////////////////////////

    function test_privateSale_list_errors() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);

        // zero address recipient
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 1 ether, address(0)));
        vm.stopPrank();

        // sanctioned recipient
        _sanction(david);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 1 ether, david));
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // listing zeroes out auction fields and stores the recipient
        vm.prank(ben);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 1 ether, 1 hours, 2 ether, david));
        Listing memory l = ah.getListing(address(nft), 1);
        assert(l.type_ == ListingType.PRIVATE_SALE);
        assertEq(l.recipient, david);
        assertEq(l.buyNowPrice, 2 ether);
        assertEq(l.reservePrice, 0);
        assertEq(l.duration, 0);
        assertEq(l.startTime, 0);
        assertEq(nft.ownerOf(1), address(ah));

        // can't bid on a private sale
        lid = l.id;
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.bid{value: 2 ether}(address(nft), 1, address(0), 2 ether, lid);

        // recipient is ignored for other listing types
        vm.prank(ben);
        ah.list(_cfg(address(nft), 2, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether, david));
        assertEq(ah.getListing(address(nft), 2).recipient, address(0));
    }

    function test_privateSale_eth_secondary(uint64 startDelay, uint256 price, address payer) public {
        // limit fuzz variables
        price = bound(price, 0, 500 ether);
        vm.assume(payer != ben && payer != tl && payer != anon && payer != david && payer != address(0));
        vm.assume(payer != address(ah) && payer.code.length == 0 && uint160(payer) > 0xff);
        vm.deal(payer, 1000 ether);

        // chris lists a private sale for david
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft),
                3,
                ListingType.PRIVATE_SALE,
                anon,
                address(0),
                block.timestamp + startDelay,
                0,
                0,
                price,
                david
            )
        );
        vm.stopPrank();
        lid = ah.getListing(address(nft), 3).id;

        // can't buy before the open time
        if (startDelay > 0) {
            vm.prank(payer);
            vm.expectRevert(TLAuctionHouse.CannotBuyYet.selector);
            ah.buyNow{value: price}(address(nft), 3, david, address(0), price, lid);
            vm.warp(block.timestamp + startDelay);
        }

        // can't deliver to anyone other than the recipient
        vm.prank(payer);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow{value: price}(address(nft), 3, payer, address(0), price, lid);

        // cache funds values
        Listing memory l = ah.getListing(address(nft), 3);
        uint256 prevPayerBalance = payer.balance;
        uint256 prevTlBalance = tl.balance;
        uint256 prevBenBalance = ben.balance;
        uint256 prevAnonBalance = anon.balance;

        // anyone can pay for the recipient
        vm.prank(payer);
        vm.expectEmit(true, true, true, true);
        emit BuyNowFulfilled(payer, address(nft), 3, david, l);
        ah.buyNow{value: price}(address(nft), 3, david, address(0), price, lid);

        // ensure funds transfer properly
        uint256 protocolFee = price * ah.protocolFeeBps() / ah.BASIS();
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, price);
        assertEq(address(ah).balance, 0);
        assertEq(prevPayerBalance - payer.balance, price);
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, amounts[0]); // secondary sale
        assertEq(anon.balance - prevAnonBalance, price - protocolFee - amounts[0]);

        // nft delivered to the recipient and listing cleared
        assertEq(nft.ownerOf(3), david);
        assert(ah.getListing(address(nft), 3).type_ == ListingType.NOT_CONFIGURED);
    }

    function test_privateSale_erc20_primary() public {
        // ben lists a private sale for david
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(coin), 0, 0, 0, 10 ether, david));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 1).id;

        // eth can't be sent with an erc20 purchase
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.buyNow{value: 1}(address(nft), 1, david, address(coin), 10 ether, lid);

        // max price protects the buyer
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.PriceTooHigh.selector);
        ah.buyNow(address(nft), 1, david, address(coin), 9 ether, lid);

        // recipient pays for themselves
        uint256 prevBenBalance = coin.balanceOf(ben);
        uint256 prevTlBalance = coin.balanceOf(tl);
        uint256 prevDavidBalance = coin.balanceOf(david);
        vm.startPrank(david);
        coin.approve(address(ah), 10 ether);
        ah.buyNow(address(nft), 1, david, address(coin), 10 ether, lid);
        vm.stopPrank();

        // primary sale, so no royalties
        uint256 protocolFee = 10 ether * ah.protocolFeeBps() / ah.BASIS();
        assertEq(prevDavidBalance - coin.balanceOf(david), 10 ether);
        assertEq(coin.balanceOf(tl) - prevTlBalance, protocolFee);
        assertEq(coin.balanceOf(ben) - prevBenBalance, 10 ether - protocolFee);
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(nft.ownerOf(1), david);
    }

    function test_privateSale_recipientSanctionedAfterListing() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 1 ether, david));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 1).id;

        // recipient gets sanctioned, so the sale can't complete
        _sanction(david);
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow{value: 1 ether}(address(nft), 1, david, address(0), 1 ether, lid);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // seller can delist
        vm.prank(ben);
        ah.delist(address(nft), 1);
        assertEq(nft.ownerOf(1), ben);
    }

    /////////////////////////////////////////////////////////////////////
    // BATCH LIST
    /////////////////////////////////////////////////////////////////////

    function test_batchList() public {
        ListingConfig[] memory configs = new ListingConfig[](2);
        configs[0] = _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0);
        configs[1] = _cfg(address(nft), 2, ListingType.PRIVATE_SALE, anon, address(coin), 0, 0, 0, 5 ether, david);

        Listing memory unchecked_;
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        vm.expectEmit(true, true, true, false);
        emit ListingConfigured(ben, address(nft), 1, unchecked_);
        vm.expectEmit(true, true, true, false);
        emit ListingConfigured(ben, address(nft), 2, unchecked_);
        ah.batchList(configs);
        vm.stopPrank();

        Listing memory l1 = ah.getListing(address(nft), 1);
        Listing memory l2 = ah.getListing(address(nft), 2);
        assert(l1.type_ == ListingType.RESERVE_AUCTION);
        assertEq(l1.seller, ben);
        assertEq(l1.reservePrice, 1 ether);
        assertEq(l1.duration, 1 hours);
        assert(l2.type_ == ListingType.PRIVATE_SALE);
        assertEq(l2.seller, ben);
        assertEq(l2.payoutReceiver, anon);
        assertEq(l2.currencyAddress, address(coin));
        assertEq(l2.recipient, david);
        assertEq(l2.id, l1.id + 1);
        assertEq(nft.ownerOf(1), address(ah));
        assertEq(nft.ownerOf(2), address(ah));

        // empty batch is a no-op
        vm.prank(ben);
        ah.batchList(new ListingConfig[](0));
    }

    function test_batchList_atomic() public {
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);
        ListingConfig[] memory configs = new ListingConfig[](2);
        configs[0] = _cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether);

        // not owner of one of the tokens
        configs[1] = _cfg(address(nft), 3, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.NotTokenOwner.selector);
        ah.batchList(configs);

        // duplicate token in the batch
        configs[1] = configs[0];
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.AlreadyListed.selector);
        ah.batchList(configs);

        // disallowed currency
        configs[1] = _cfg(address(nft), 2, ListingType.BUY_NOW, ben, makeAddr("not a currency"), 0, 0, 0, 1 ether);
        vm.prank(ben);
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        ah.batchList(configs);

        // invalid listing
        configs[1] = _cfg(address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(0), 0, 0, 31 days, 0);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        ah.batchList(configs);

        // nothing was listed
        assertEq(nft.ownerOf(1), ben);
        assertEq(nft.ownerOf(2), ben);
        assert(ah.getListing(address(nft), 1).type_ == ListingType.NOT_CONFIGURED);
    }

    function test_batchList_pausedAndSanctioned() public {
        ListingConfig[] memory configs = new ListingConfig[](1);
        configs[0] = _cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether);
        vm.prank(ben);
        nft.setApprovalForAll(address(ah), true);

        ah.pause(true);
        vm.prank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.batchList(configs);
        ah.pause(false);

        _sanction(ben);
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.batchList(configs);
        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    // TOP UP BID
    /////////////////////////////////////////////////////////////////////

    function test_topUpBid_errors() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether));
        ah.list(_cfg(address(nft), 2, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0));
        vm.stopPrank();

        // not an auction
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 1, 1 ether, lid);

        // no bids yet
        lid = ah.getListing(address(nft), 2).id;
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotHighestBidder.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid);

        // chris bids
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 2, address(0), 1 ether, lid);

        // not the highest bidder
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.NotHighestBidder.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid);

        // stale listing id
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid + 1);

        // zero amount
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.topUpBid(address(nft), 2, 0, lid);

        // wrong msg.value
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.topUpBid{value: 0.5 ether}(address(nft), 2, 1 ether, lid);

        // paused
        ah.pause(true);
        vm.prank(chris);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid);
        ah.pause(false);

        // sanctioned
        _sanction(chris);
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // auction ended
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 2, 1 ether, lid);

        // nothing changed
        assertEq(ah.getListing(address(nft), 2).highestBid, 1 ether);
        assertEq(address(ah).balance, 1 ether);
    }

    function test_topUpBid_eth(uint256 firstBid, uint256 topUp) public {
        firstBid = bound(firstBid, 1, 100 ether);
        topUp = bound(topUp, 1, 100 ether);

        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 0, 1 hours, 0));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 1).id;

        vm.prank(chris);
        ah.bid{value: firstBid}(address(nft), 1, address(0), firstBid, lid);

        // top up in the last minute doesn't extend the auction
        vm.warp(block.timestamp + 59 minutes);
        Listing memory l = ah.getListing(address(nft), 1);
        l.highestBid += topUp;
        uint256 prevChrisBalance = chris.balance;
        vm.prank(chris);
        vm.expectEmit(true, true, true, true);
        emit AuctionBidToppedUp(chris, address(nft), 1, topUp, l);
        ah.topUpBid{value: topUp}(address(nft), 1, topUp, lid);

        l = ah.getListing(address(nft), 1);
        assertEq(l.highestBid, firstBid + topUp);
        assertEq(l.highestBidder, chris);
        assertEq(l.duration, 1 hours);
        assertEq(l.id, lid);
        assertEq(prevChrisBalance - chris.balance, topUp);
        assertEq(address(ah).balance, firstBid + topUp);

        // next bid is based on the topped up amount
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        assertEq(nextBid, (firstBid + topUp) + Math.mulDiv(firstBid + topUp, 500, 10_000, Math.Rounding.Ceil));

        // settle pays out the topped up amount (primary sale)
        vm.warp(block.timestamp + 1 minutes + 1);
        uint256 prevBenBalance = ben.balance;
        uint256 prevTlBalance = tl.balance;
        ah.settleAuction(address(nft), 1);
        uint256 protocolFee = (firstBid + topUp) * ah.protocolFeeBps() / ah.BASIS();
        assertEq(tl.balance - prevTlBalance, protocolFee);
        assertEq(ben.balance - prevBenBalance, firstBid + topUp - protocolFee);
        assertEq(address(ah).balance, 0);
        assertEq(nft.ownerOf(1), chris);
    }

    function test_topUpBid_outbidRefundsFullAmount() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 1).id;

        uint256 prevChrisBalance = chris.balance;
        vm.startPrank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);
        ah.topUpBid{value: 0.5 ether}(address(nft), 1, 0.5 ether, lid);
        ah.topUpBid{value: 0.25 ether}(address(nft), 1, 0.25 ether, lid);
        vm.stopPrank();
        assertEq(ah.getListing(address(nft), 1).highestBid, 1.75 ether);

        // david can't outbid with less than the next bid on the topped up amount
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid{value: 1.8 ether}(address(nft), 1, address(0), 1.8 ether, lid);

        // david outbids and chris gets everything back
        uint256 nextBid = ah.getNextBid(address(nft), 1);
        vm.prank(david);
        ah.bid{value: nextBid}(address(nft), 1, address(0), nextBid, lid);
        assertEq(chris.balance, prevChrisBalance);
        assertEq(address(ah).balance, nextBid);

        // chris can no longer top up
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotHighestBidder.selector);
        ah.topUpBid{value: 1 ether}(address(nft), 1, 1 ether, lid);
    }

    function test_topUpBid_erc20() public {
        vm.startPrank(chris);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 3, ListingType.SCHEDULED_AUCTION, chris, address(coin), 0, 0, 1 hours, 0));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 3).id;

        vm.startPrank(david);
        coin.approve(address(ah), 10 ether);
        ah.bid(address(nft), 3, address(coin), 1 ether, lid);

        // eth can't be sent with an erc20 top up
        vm.expectRevert(TLAuctionHouse.UnexpectedMsgValue.selector);
        ah.topUpBid{value: 1}(address(nft), 3, 1 ether, lid);

        uint256 prevDavidBalance = coin.balanceOf(david);
        ah.topUpBid(address(nft), 3, 2 ether, lid);
        vm.stopPrank();
        assertEq(prevDavidBalance - coin.balanceOf(david), 2 ether);
        assertEq(coin.balanceOf(address(ah)), 3 ether);
        assertEq(ah.getListing(address(nft), 3).highestBid, 3 ether);

        // settle pays out the topped up amount (secondary sale)
        vm.warp(block.timestamp + 1 hours + 1);
        uint256 prevChrisBalance = coin.balanceOf(chris);
        uint256 prevBenBalance = coin.balanceOf(ben);
        ah.settleAuction(address(nft), 3);
        uint256 protocolFee = 3 ether * ah.protocolFeeBps() / ah.BASIS();
        (, uint256[] memory amounts) = ah.getRoyalty(address(nft), 3, 3 ether);
        assertEq(coin.balanceOf(ben) - prevBenBalance, amounts[0]);
        assertEq(coin.balanceOf(chris) - prevChrisBalance, 3 ether - protocolFee - amounts[0]);
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(nft.ownerOf(3), david);
    }

    /////////////////////////////////////////////////////////////////////
    // UPDATE LISTING
    /////////////////////////////////////////////////////////////////////

    function test_updateListing_errors() public {
        ListingConfig memory c =
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0);

        // not listed
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.updateListing(c);

        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(c);
        vm.stopPrank();

        // not seller
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.updateListing(c);

        // listing type can't change
        c.type_ = ListingType.BUY_NOW;
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidListingType.selector);
        ah.updateListing(c);
        c.type_ = ListingType.RESERVE_AUCTION;

        // currency can't change
        c.currencyAddress = address(coin);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.CurrencyMismatch.selector);
        ah.updateListing(c);
        c.currencyAddress = address(0);

        // invalid payout receiver
        c.payoutReceiver = address(0);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.updateListing(c);
        c.payoutReceiver = ben;

        // duration too long
        c.auctionDuration = 31 days;
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidDuration.selector);
        ah.updateListing(c);
        c.auctionDuration = 1 hours;

        // paused
        ah.pause(true);
        vm.prank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.updateListing(c);
        ah.pause(false);

        // sanctioned seller
        _sanction(ben);
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.updateListing(c);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // can't update after the first bid
        lid = ah.getListing(address(nft), 1).id;
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.AuctionStarted.selector);
        ah.updateListing(c);
    }

    function test_updateListing_reserveAuction(uint256 reservePrice, uint256 duration, address payoutReceiver) public {
        reservePrice = bound(reservePrice, 1, 100 ether);
        duration = bound(duration, 1, 30 days);
        vm.assume(payoutReceiver != address(0) && payoutReceiver != tl);

        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0));
        vm.stopPrank();
        ah.removeProtocolFee(address(nft), 1);
        uint256 oldId = ah.getListing(address(nft), 1).id;

        // expected listing after the update
        Listing memory expected = Listing({
            type_: ListingType.RESERVE_AUCTION,
            zeroProtocolFee: true,
            seller: ben,
            payoutReceiver: payoutReceiver,
            currencyAddress: address(0),
            openTime: block.timestamp,
            reservePrice: reservePrice,
            buyNowPrice: 0,
            startTime: 0,
            duration: duration,
            recipient: address(0),
            highestBidder: address(0),
            highestBid: 0,
            id: oldId + 1
        });

        vm.prank(ben);
        vm.expectEmit(true, true, true, true);
        emit ListingUpdated(ben, address(nft), 1, expected);
        ah.updateListing(
            _cfg(address(nft), 1, ListingType.RESERVE_AUCTION, payoutReceiver, address(0), 0, reservePrice, duration, 5)
        );

        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(abi.encode(l), abi.encode(expected));
        assertEq(nft.ownerOf(1), address(ah));

        // bids against the old listing fail
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, oldId);

        // bids against the new listing work, with the protocol fee still removed
        vm.prank(chris);
        ah.bid{value: reservePrice}(address(nft), 1, address(0), reservePrice, l.id);
        vm.warp(block.timestamp + ah.getListing(address(nft), 1).duration + 1);
        uint256 prevTlBalance = tl.balance;
        ah.settleAuction(address(nft), 1);
        assertEq(tl.balance, prevTlBalance);
        assertEq(nft.ownerOf(1), chris);
    }

    function test_updateListing_scheduledAuction() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), 0, 0, 1 hours, 0));

        // push the auction out a day and change the duration
        uint256 openTime = block.timestamp + 1 days;
        ah.updateListing(
            _cfg(address(nft), 1, ListingType.SCHEDULED_AUCTION, ben, address(0), openTime, 1 ether, 2 hours, 1 ether)
        );
        vm.stopPrank();

        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.openTime, openTime);
        assertEq(l.startTime, openTime);
        assertEq(l.duration, 2 hours);
        assertEq(l.reservePrice, 1 ether);
        assertEq(l.buyNowPrice, 0);

        // can't bid until the new open time
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.CannotBidYet.selector);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, l.id);

        vm.warp(openTime);
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, l.id);
        assertEq(ah.getListing(address(nft), 1).highestBidder, chris);
    }

    function test_updateListing_buyNow() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.BUY_NOW, ben, address(0), 0, 0, 0, 1 ether));
        uint256 oldId = ah.getListing(address(nft), 1).id;
        ah.updateListing(_cfg(address(nft), 1, ListingType.BUY_NOW, anon, address(0), 0, 1 ether, 1 hours, 2 ether));
        vm.stopPrank();

        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.buyNowPrice, 2 ether);
        assertEq(l.payoutReceiver, anon);
        assertEq(l.reservePrice, 0);
        assertEq(l.duration, 0);

        // buys against the old listing fail
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.buyNow{value: 2 ether}(address(nft), 1, chris, address(0), 2 ether, oldId);

        uint256 prevAnonBalance = anon.balance;
        vm.prank(chris);
        ah.buyNow{value: 2 ether}(address(nft), 1, chris, address(0), 2 ether, l.id);
        assertEq(anon.balance - prevAnonBalance, 2 ether - 2 ether * ah.protocolFeeBps() / ah.BASIS());
        assertEq(nft.ownerOf(1), chris);
    }

    function test_updateListing_reserveAuctionPlusBuyNow() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(
            _cfg(
                address(nft), 1, ListingType.RESERVE_AUCTION_PLUS_BUY_NOW, ben, address(0), 0, 1 ether, 1 hours, 5 ether
            )
        );
        ah.updateListing(
            _cfg(
                address(nft), 1, ListingType.RESERVE_AUCTION_PLUS_BUY_NOW, ben, address(0), 0, 2 ether, 1 hours, 3 ether
            )
        );
        vm.stopPrank();

        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.reservePrice, 2 ether);
        assertEq(l.buyNowPrice, 3 ether);

        // old reserve no longer valid
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.BidTooLow.selector);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, l.id);

        vm.prank(chris);
        ah.buyNow{value: 3 ether}(address(nft), 1, chris, address(0), 3 ether, l.id);
        assertEq(nft.ownerOf(1), chris);
    }

    function test_updateListing_privateSale() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 1 ether, david));

        // recipient can't be the zero address
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.updateListing(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 1 ether, address(0)));

        // change the recipient and price
        ah.updateListing(_cfg(address(nft), 1, ListingType.PRIVATE_SALE, ben, address(0), 0, 0, 0, 2 ether, bsy));
        vm.stopPrank();

        Listing memory l = ah.getListing(address(nft), 1);
        assertEq(l.recipient, bsy);
        assertEq(l.buyNowPrice, 2 ether);

        // previous recipient can no longer receive
        vm.prank(david);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow{value: 2 ether}(address(nft), 1, david, address(0), 2 ether, l.id);

        vm.prank(david);
        ah.buyNow{value: 2 ether}(address(nft), 1, bsy, address(0), 2 ether, l.id);
        assertEq(nft.ownerOf(1), bsy);
    }

    /////////////////////////////////////////////////////////////////////
    // UPDATE PAYOUT RECEIVER
    /////////////////////////////////////////////////////////////////////

    function test_updatePayoutReceiver() public {
        // not listed
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.updatePayoutReceiver(address(nft), 1, anon);

        vm.startPrank(ben);
        nft.setApprovalForAll(address(ah), true);
        ah.list(_cfg(address(nft), 1, ListingType.RESERVE_AUCTION, ben, address(0), 0, 1 ether, 1 hours, 0));
        vm.stopPrank();
        lid = ah.getListing(address(nft), 1).id;

        // not seller
        vm.prank(chris);
        vm.expectRevert(TLAuctionHouse.NotSeller.selector);
        ah.updatePayoutReceiver(address(nft), 1, chris);

        // invalid payout receiver
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.updatePayoutReceiver(address(nft), 1, address(0));

        // sanctioned payout receiver
        _sanction(anon);
        vm.prank(ben);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.updatePayoutReceiver(address(nft), 1, anon);
        vm.clearMockedCalls();

        // sanctioned seller
        _sanction(ben);
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.updatePayoutReceiver(address(nft), 1, anon);
        vm.clearMockedCalls();
        ah.setSanctionsOracle(address(0));

        // paused
        ah.pause(true);
        vm.prank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ah.updatePayoutReceiver(address(nft), 1, anon);
        ah.pause(false);

        // update before bids
        vm.prank(ben);
        ah.updatePayoutReceiver(address(nft), 1, anon);
        assertEq(ah.getListing(address(nft), 1).payoutReceiver, anon);
        assertEq(ah.getListing(address(nft), 1).id, lid);

        // update after bids keeps the listing id, so pending bids still land
        vm.prank(chris);
        ah.bid{value: 1 ether}(address(nft), 1, address(0), 1 ether, lid);
        Listing memory expected = ah.getListing(address(nft), 1);
        expected.payoutReceiver = bsy;
        vm.prank(ben);
        vm.expectEmit(true, true, true, true);
        emit ListingUpdated(ben, address(nft), 1, expected);
        ah.updatePayoutReceiver(address(nft), 1, bsy);
        assertEq(abi.encode(ah.getListing(address(nft), 1)), abi.encode(expected));

        vm.prank(david);
        ah.bid{value: 2 ether}(address(nft), 1, address(0), 2 ether, lid);

        // settlement pays the new payout receiver (primary sale)
        vm.warp(block.timestamp + 1 hours + 1);
        uint256 prevBsyBalance = bsy.balance;
        uint256 prevAnonBalance = anon.balance;
        ah.settleAuction(address(nft), 1);
        assertEq(bsy.balance - prevBsyBalance, 2 ether - 2 ether * ah.protocolFeeBps() / ah.BASIS());
        assertEq(anon.balance, prevAnonBalance);
        assertEq(nft.ownerOf(1), david);
    }
}

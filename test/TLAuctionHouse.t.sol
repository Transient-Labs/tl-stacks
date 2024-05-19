// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {ERC721TL} from "tl-creator-contracts/erc-721/ERC721TL.sol";
import {WETH9} from "tl-sol-tools/../test/utils/WETH9.sol";
import {IChainalysisSanctionsOracle, SanctionsCompliance} from "tl-sol-tools/payments/SanctionsCompliance.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {ITLAuctionHouseEvents, Auction, Sale} from "src/utils/TLAuctionHouseUtils.sol";
import {AuctionHouseErrors} from "src/utils/CommonUtils.sol";
import {Receiver, RevertingBidder, GriefingBidder} from "test/utils/Receiver.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MaliciousERC721} from "test/utils/MaliciousERC721.sol";

contract TLAuctionHouseTest is Test, ITLAuctionHouseEvents, AuctionHouseErrors {
    address wethAddress;
    TLAuctionHouse auctionHouse;
    ERC721TL nft;
    MockERC20 coin;

    bytes32[] emptyProof = new bytes32[](0);

    address receiver;

    address tl = makeAddr("Build Different");
    uint256 feePerc = 100;
    uint256 feeLimit = 0.42 ether;
    uint256 minBidIncreasePerc = 500;
    uint256 minBidIncreaseLimit = 1 ether;
    address royaltyEngine = makeAddr("Royalty Engine");

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);
    address bsy = address(0xCDB);
    address anon = address(0x404);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        wethAddress = address(new WETH9());
        auctionHouse = new TLAuctionHouse(
            address(this),
            address(0),
            wethAddress,
            royaltyEngine,
            tl,
            minBidIncreasePerc,
            minBidIncreaseLimit,
            feePerc,
            feeLimit
        );

        address[] memory empty = new address[](0);

        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", "", address(this), 1_000, address(this), empty, false, address(0), address(0));
        nft.mint(ben, "https://arweave.net/NO-BEEF");
        nft.mint(ben, "https://arweave.net/NO-BEEF-2");
        nft.mint(chris, "https://arweave.net/MORE-COFFEE");

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

    /// @dev test deployment
    function test_setUp() public {
        assertEq(auctionHouse.owner(), address(this));
        assertEq(auctionHouse.weth(), wethAddress);
        assertEq(auctionHouse.minBidIncreasePerc(), minBidIncreasePerc);
        assertEq(auctionHouse.minBidIncreaseLimit(), minBidIncreaseLimit);
        assertEq(auctionHouse.protocolFeePerc(), feePerc);
        assertEq(auctionHouse.protocolFeeLimit(), feeLimit);
        assertEq(auctionHouse.protocolFeeReceiver(), tl);
        assertFalse(auctionHouse.paused());
    }

    /// @dev test owner only acccess
    function test_ownerOnlyAccess(address sender) public {
        vm.assume(sender != address(this));

        // revert for sender (non-owner)
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.pause(true);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.pause(false);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.transferOwnership(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.setWethAddress(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.setRoyaltyEngine(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.setProtocolFeeSettings(sender, 500, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        auctionHouse.setMinBidIncreaseSettings(1000, 1 ether);
        vm.stopPrank();

        // pass for owner
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), address(this));
        auctionHouse.transferOwnership(address(this));
        vm.expectEmit(true, true, false, false);
        emit RoyaltyEngineUpdated(royaltyEngine, address(0));
        auctionHouse.setRoyaltyEngine(address(0));
        assertEq(address(auctionHouse.royaltyEngine()), address(0));
        vm.expectEmit(true, true, false, false);
        emit WethUpdated(wethAddress, address(0));
        auctionHouse.setWethAddress(address(0));
        assertEq(auctionHouse.weth(), address(0));
        vm.expectEmit(true, true, true, false);
        emit ProtocolFeeUpdated(address(this), 500, 1 ether);
        auctionHouse.setProtocolFeeSettings(address(this), 500, 1 ether);
        assertEq(auctionHouse.protocolFeeReceiver(), address(this));
        assertEq(auctionHouse.protocolFeePerc(), 500);
        assertEq(auctionHouse.protocolFeeLimit(), 1 ether);
        vm.expectEmit(true, true, false, false);
        emit MinBidIncreaseUpdated(1000, 2 ether);
        auctionHouse.setMinBidIncreaseSettings(1000, 2 ether);
        assertEq(auctionHouse.minBidIncreasePerc(), 1000);
        assertEq(auctionHouse.minBidIncreaseLimit(), 2 ether);
        vm.expectEmit(false, false, false, true);
        emit Paused(address(this));
        auctionHouse.pause(true);
        vm.expectEmit(false, false, false, true);
        emit Unpaused(address(this));
        auctionHouse.pause(false);
    }

    /// @dev test that pausing the contract blocks all applicable functions
    function test_paused() public {
        auctionHouse.pause(true);

        vm.startPrank(ben);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, true);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        auctionHouse.bid(address(nft), 1, 100);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        auctionHouse.buyNow(address(nft), 1);
        vm.stopPrank();
    }

    /// @dev test owner configuration errors
    function test_ownerConfigErrors() public {
        vm.expectRevert(PercentageTooLarge.selector);
        auctionHouse.setMinBidIncreaseSettings(10_001, 1 ether);

        vm.expectRevert(PercentageTooLarge.selector);
        auctionHouse.setProtocolFeeSettings(address(this), 10_001, 1 ether);
    }

    /// @dev test configuring auctions
    function test_configureAuction(
        address hacker,
        address payoutReceiver,
        bool useEth,
        uint256 reservePrice,
        uint256 auctionOpenTime,
        uint256 duration,
        bool reserveAuction
    ) public {
        // limit fuzz inputs
        vm.assume(hacker != ben && hacker != address(0));
        vm.assume(payoutReceiver != address(0));
        if (reservePrice > 1000 ether) {
            reservePrice = reservePrice % 1000 ether;
        }
        if (duration > 1_000_000 days) {
            duration = duration % 1_000_000 days;
        }

        uint256 startTime = reserveAuction ? 0 : auctionOpenTime;

        address currencyAddress = useEth ? address(0) : address(coin);

        // not token owner
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );

        // auction house not approved
        vm.expectRevert(AuctionHouseNotApproved.selector);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );

        // approve token auction house - fail
        vm.prank(ben);
        nft.approve(address(auctionHouse), 1);
        vm.expectRevert(AuctionHouseNotApproved.selector);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );

        // approve auction house for all
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);

        // zero address payout receiver
        vm.expectRevert(PayoutToZeroAddress.selector);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, address(0), currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );

        // configure auction
        Auction memory auction = Auction(
            ben, payoutReceiver, currencyAddress, address(0), 0, reservePrice, auctionOpenTime, startTime, duration
        );
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );
        Auction memory rAuction = auctionHouse.getAuction(address(nft), 1);
        assert(rAuction.seller == auction.seller);
        assert(rAuction.payoutReceiver == auction.payoutReceiver);
        assert(rAuction.currencyAddress == auction.currencyAddress);
        assert(rAuction.highestBid == auction.highestBid);
        assert(rAuction.highestBidder == auction.highestBidder);
        assert(rAuction.reservePrice == auction.reservePrice);
        assert(rAuction.auctionOpenTime == auction.auctionOpenTime);
        assert(rAuction.startTime == auction.startTime);
        assert(rAuction.duration == auction.duration);

        // override auction
        auction.reservePrice = reservePrice + 1;
        auction.duration = duration + 1;
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft),
            1,
            payoutReceiver,
            currencyAddress,
            reservePrice + 1,
            auctionOpenTime,
            duration + 1,
            reserveAuction
        );
        rAuction = auctionHouse.getAuction(address(nft), 1);
        assert(rAuction.seller == auction.seller);
        assert(rAuction.payoutReceiver == auction.payoutReceiver);
        assert(rAuction.currencyAddress == auction.currencyAddress);
        assert(rAuction.highestBid == auction.highestBid);
        assert(rAuction.highestBidder == auction.highestBidder);
        assert(rAuction.reservePrice == auction.reservePrice);
        assert(rAuction.auctionOpenTime == auction.auctionOpenTime);
        assert(rAuction.startTime == auction.startTime);
        assert(rAuction.duration == auction.duration);

        // transfer nft and then override auction
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        vm.prank(chris);
        nft.setApprovalForAll(address(auctionHouse), true);
        auction.seller = chris;
        auction.reservePrice = reservePrice;
        auction.duration = duration;
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(chris, address(nft), 1, auction);
        vm.prank(chris);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, reservePrice, auctionOpenTime, duration, reserveAuction
        );
        rAuction = auctionHouse.getAuction(address(nft), 1);
        assert(rAuction.seller == auction.seller);
        assert(rAuction.payoutReceiver == auction.payoutReceiver);
        assert(rAuction.currencyAddress == auction.currencyAddress);
        assert(rAuction.highestBid == auction.highestBid);
        assert(rAuction.highestBidder == auction.highestBidder);
        assert(rAuction.reservePrice == auction.reservePrice);
        assert(rAuction.auctionOpenTime == auction.auctionOpenTime);
        assert(rAuction.startTime == auction.startTime);
        assert(rAuction.duration == auction.duration);
    }

    /// @dev test canceling an auction
    function test_cancelAuction(address hacker, bool reserveAuction) public {
        // limit fuzz input
        vm.assume(hacker != ben && hacker != chris && hacker != address(0));

        // cancel nonexistent auction (should pass but waste of gas)
        vm.prank(ben);
        auctionHouse.cancelAuction(address(nft), 1);

        // setup auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, reserveAuction);

        // not token owner
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.cancelAuction(address(nft), 1);

        // successfully cancel auction
        vm.expectEmit(true, true, true, false);
        emit AuctionCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelAuction(address(nft), 1);

        // create auction again
        vm.prank(ben);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, reserveAuction);

        // transfer token and still be able to cancel if seller calls
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.cancelAuction(address(nft), 1);
        vm.expectEmit(true, true, true, false);
        emit AuctionCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelAuction(address(nft), 1);

        // create auction again
        vm.prank(chris);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(chris);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, reserveAuction);

        // transfer token and the new owner can cancel the auction
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);
        vm.expectEmit(true, true, true, false);
        emit AuctionCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelAuction(address(nft), 1);

        // create auction again
        vm.prank(ben);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, reserveAuction);

        // start auction
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);

        // try to cancel with auction in progress
        vm.expectRevert(AuctionStarted.selector);
        vm.prank(ben);
        auctionHouse.cancelAuction(address(nft), 1);
    }

    /// @dev test buy now with malicious nft
    function test_reserveAuctionMaliciousNft() public {
        // malicious nft
        MaliciousERC721 mnft = new MaliciousERC721();
        mnft.mint(ben);
        mnft.setBeMalicious(true);

        // configure sale
        vm.prank(ben);
        mnft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(address(mnft), 1, ben, address(0), 1, block.timestamp, 24 hours, true);

        // revert on first bid
        vm.prank(chris);
        vm.expectRevert(NftNotTransferred.selector);
        auctionHouse.bid{value: 1.01 ether}(address(mnft), 1, 1 ether);

        // allow bid
        mnft.setBeMalicious(false);

        // bid
        vm.prank(chris);
        auctionHouse.bid{value: 1.01 ether}(address(mnft), 1, 1 ether);

        // settle auction error
        mnft.setBeMalicious(true);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(chris);
        vm.expectRevert(NftNotTransferred.selector);
        auctionHouse.settleAuction(address(mnft), 1);
    }

    /// @dev test buy now with malicious nft
    function test_scheduledAuctionMaliciousNft() public {
        // malicious nft
        MaliciousERC721 mnft = new MaliciousERC721();
        mnft.mint(ben);
        mnft.setBeMalicious(true);

        // configure sale
        vm.prank(ben);
        mnft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(address(mnft), 1, ben, address(0), 1, block.timestamp, 24 hours, false);

        // revert on first bid
        vm.prank(chris);
        vm.expectRevert(NftNotTransferred.selector);
        auctionHouse.bid{value: 1.01 ether}(address(mnft), 1, 1 ether);

        // allow bid
        mnft.setBeMalicious(false);

        // bid
        vm.prank(chris);
        auctionHouse.bid{value: 1.01 ether}(address(mnft), 1, 1 ether);

        // settle auction error
        mnft.setBeMalicious(true);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(chris);
        vm.expectRevert(NftNotTransferred.selector);
        auctionHouse.settleAuction(address(mnft), 1);
    }

    /// @dev test bid eth errors
    function test_bidEthErrors(bool reserveAuction) public {
        // auction not configured
        vm.expectRevert(AuctionNotConfigured.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, ben, address(0), 1, block.timestamp + 1000, 24 hours, reserveAuction
        );

        // auction not open
        vm.expectRevert(AuctionNotOpen.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 1}(address(nft), 1, 1);

        // warp
        vm.warp(block.timestamp + 1000);

        // bid below reserve price
        vm.expectRevert(BidTooLow.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 0}(address(nft), 1, 0);

        // insufficient eth
        vm.expectRevert(InsufficientMsgValue.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 0}(address(nft), 1, 1);

        // nft not owned by the seller
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        uint256 fee = auctionHouse.calcProtocolFee(1);
        vm.expectRevert(NftNotOwnedBySeller.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);

        // return nft
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);

        // kick off auction
        vm.prank(bsy);
        auctionHouse.bid{value: 1 + fee}(address(nft), 1, 1);

        // bid too low on started auction
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        vm.expectRevert(BidTooLow.selector);
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid - 1);

        // insufficient eth
        vm.expectRevert(InsufficientMsgValue.selector);
        vm.prank(david);
        auctionHouse.bid{value: nextBid + fee - 1}(address(nft), 1, nextBid);

        // warp
        vm.warp(block.timestamp + 24 hours + 1);

        // auction ended
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(david);
        auctionHouse.bid{value: nextBid + fee}(address(nft), 1, nextBid);
    }

    /// @dev test bid ERC20 errors
    function test_bidERC20Errors(bool reserveAuction) public {
        // auction not configured
        vm.expectRevert(AuctionNotConfigured.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, ben, address(coin), 1, block.timestamp + 1000, 24 hours, reserveAuction
        );

        // auction not open
        vm.expectRevert(AuctionNotOpen.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);

        // warp
        vm.warp(block.timestamp + 1000);

        // bid below reserve price
        vm.expectRevert(BidTooLow.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);

        // insufficient erc20 approval
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(auctionHouse), 0, 1)
        );
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);
        vm.prank(bsy);
        coin.approve(address(auctionHouse), 1 ether);

        // insufficient erc20 balance
        vm.prank(bsy);
        coin.transfer(ben, 10000 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bsy, 0, 1));
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);

        // return funds to bsy
        vm.prank(ben);
        coin.transfer(bsy, 10000 ether);

        // nft not owned by the seller
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        uint256 fee = auctionHouse.calcProtocolFee(1);
        vm.expectRevert(NftNotOwnedBySeller.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);

        // return nft
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);

        // kick off auction
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 1);

        // bid too low on started auction
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        vm.expectRevert(BidTooLow.selector);
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid - 1);

        // insufficient erc20 approval
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(auctionHouse), 0, nextBid + fee
            )
        );
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid);
        vm.prank(david);
        coin.approve(address(auctionHouse), 1 ether);

        /// insufficint erc20 balance
        vm.prank(david);
        coin.transfer(ben, 10000 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, david, 0, nextBid + fee));
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid);

        // warp
        vm.warp(block.timestamp + 24 hours + 1);

        // auction ended
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid);
    }

    /// @dev test refund bid eth
    function test_refundEthBid(uint256 reservePrice, uint256 extra, bool reserveAuction) public {
        // limit fuzz variables
        if (reservePrice > 100 ether) {
            reservePrice = reservePrice % 100 ether;
        }
        if (extra > 100 ether) {
            extra = extra % 100 ether;
        }

        // configure auction
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(0), reservePrice, block.timestamp, 24 hours, reserveAuction
        );
        vm.stopPrank();

        // meet reserve
        uint256 prevAHBalance = address(auctionHouse).balance;
        uint256 prevSenderBalance = bsy.balance;
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice);
        vm.prank(bsy);
        auctionHouse.bid{value: reservePrice + fee + extra}(address(nft), 1, reservePrice);
        assert(address(auctionHouse).balance - prevAHBalance == reservePrice + fee);
        assert(prevSenderBalance - bsy.balance == reservePrice + fee);

        // second bid
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        prevSenderBalance = david.balance;
        vm.prank(david);
        auctionHouse.bid{value: nextBid + fee + extra}(address(nft), 1, nextBid);
        assert(address(auctionHouse).balance - prevAHBalance == nextBid + fee);
        assert(prevSenderBalance - david.balance == nextBid + fee);
    }

    /// @dev test refund bid erc20
    function test_refundERC20Bid(uint256 reservePrice, uint256 extra, bool reserveAuction) public {
        // limit fuzz variables
        if (reservePrice > 100 ether) {
            reservePrice = reservePrice % 100 ether;
        }
        if (extra > 100 ether) {
            extra = extra % 100 ether;
        }

        // configure auction
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(coin), reservePrice, block.timestamp, 24 hours, reserveAuction
        );
        vm.stopPrank();

        // approve coin
        vm.prank(bsy);
        coin.approve(address(auctionHouse), 1000 ether);
        vm.prank(david);
        coin.approve(address(auctionHouse), 1000 ether);

        // meet reserve
        uint256 prevAHEthBalance = coin.balanceOf(address(auctionHouse));
        uint256 prevSenderEthBalance = bsy.balance;
        uint256 prevSenderCoinBalance = coin.balanceOf(bsy);
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice);
        vm.prank(bsy);
        auctionHouse.bid{value: extra}(address(nft), 1, reservePrice);
        assert(coin.balanceOf(address(auctionHouse)) - prevAHEthBalance == reservePrice + fee);
        assert(prevSenderCoinBalance - coin.balanceOf(bsy) == reservePrice + fee);
        assert(prevSenderEthBalance - bsy.balance == 0);

        // second bid
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        prevSenderEthBalance = david.balance;
        prevSenderCoinBalance = coin.balanceOf(david);
        vm.prank(david);
        auctionHouse.bid{value: extra}(address(nft), 1, nextBid);
        assert(coin.balanceOf(address(auctionHouse)) - prevAHEthBalance == nextBid + fee);
        assert(prevSenderCoinBalance - coin.balanceOf(david) == nextBid + fee);
        assert(prevSenderEthBalance - david.balance == 0);
    }

    /// @dev test bidder with reverting receiver function
    function test_revertingBidder(uint256 reservePrice, bool reserveAuction) public {
        // limit fuzz variables
        if (reservePrice > 100 ether) {
            reservePrice = reservePrice % 100 ether;
        }

        // configure auction
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(0), reservePrice, block.timestamp, 24 hours, reserveAuction
        );
        vm.stopPrank();

        // meet reserve
        uint256 prevAHBalance = address(auctionHouse).balance;
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice);
        vm.prank(bsy);
        auctionHouse.bid{value: reservePrice + fee}(address(nft), 1, reservePrice);
        assert(address(auctionHouse).balance - prevAHBalance == reservePrice + fee);

        // bid with bidder that reverts on eth received
        GriefingBidder bidder = new GriefingBidder(address(auctionHouse));
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        vm.prank(david);
        bidder.bid{value: nextBid + fee}(address(nft), 1, nextBid);
        assert(address(auctionHouse).balance - prevAHBalance == nextBid + fee);

        // bid again and reverting bidder shouldn't lock the contract
        uint256 nextNextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 nextFee = auctionHouse.calcProtocolFee(nextNextBid);
        vm.prank(bsy);
        auctionHouse.bid{value: nextNextBid + nextFee}(address(nft), 1, nextNextBid);
        assert(address(auctionHouse).balance - prevAHBalance == nextNextBid + nextFee);
        assert(WETH9(payable(wethAddress)).balanceOf(address(bidder)) == nextBid + fee);
    }

    /// @dev test bidder with griefing receiver function
    function test_griefingBidder(uint256 reservePrice, bool reserveAuction) public {
        // limit fuzz variables
        if (reservePrice > 100 ether) {
            reservePrice = reservePrice % 100 ether;
        }

        // configure auction
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(0), reservePrice, block.timestamp, 24 hours, reserveAuction
        );
        vm.stopPrank();

        // meet reserve
        uint256 prevAHBalance = address(auctionHouse).balance;
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice);
        vm.prank(bsy);
        auctionHouse.bid{value: reservePrice + fee}(address(nft), 1, reservePrice);
        assert(address(auctionHouse).balance - prevAHBalance == reservePrice + fee);

        // bid with bidder that reverts on eth received
        RevertingBidder bidder = new RevertingBidder(address(auctionHouse));
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        fee = auctionHouse.calcProtocolFee(nextBid);
        vm.prank(david);
        bidder.bid{value: nextBid + fee}(address(nft), 1, nextBid);
        assert(address(auctionHouse).balance - prevAHBalance == nextBid + fee);

        // bid again and griefing bidder shouldn't lock the contract
        uint256 nextNextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 nextFee = auctionHouse.calcProtocolFee(nextNextBid);
        vm.prank(bsy);
        auctionHouse.bid{value: nextNextBid + nextFee, gas: 30_000_000}(address(nft), 1, nextNextBid);
        assert(address(auctionHouse).balance - prevAHBalance == nextNextBid + nextFee);
        assert(WETH9(payable(wethAddress)).balanceOf(address(bidder)) == nextBid + fee);
    }

    /// @dev test settle auction errors
    function test_settleAuctionErrors(bool reserveAuction, uint256 waitTime) public {
        if (waitTime >= 24 hours) {
            waitTime = waitTime % 24 hours;
        }
        // auction not configured
        vm.expectRevert(AuctionNotStarted.selector);
        auctionHouse.settleAuction(address(nft), 1);

        // auction not started
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, reserveAuction);
        vm.expectRevert(AuctionNotStarted.selector);
        auctionHouse.settleAuction(address(nft), 1);

        // auction not ended
        vm.warp(block.timestamp + waitTime);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);
        vm.expectRevert(AuctionNotEnded.selector);
        auctionHouse.settleAuction(address(nft), 1);
    }

    /// @dev test bid & settle with eth - reserve auction
    function test_bidEth_reserveAuction(uint256 reservePrice, uint256 startDelay, uint256 duration, uint256 bidExtra)
        public
    {
        // limit fuzz variables
        if (reservePrice > 500 ether) {
            reservePrice = reservePrice % 500 ether;
        }
        if (startDelay > 300 days) {
            startDelay = startDelay % 300 days;
        }
        if (duration > 300 days) {
            duration = duration % 300 days;
        }
        if (bidExtra > 200 ether) {
            bidExtra = bidExtra % 200 ether;
        }

        // initial variables
        uint256 initAhBalance = address(auctionHouse).balance;
        Auction memory auction =
            Auction(ben, receiver, address(0), address(0), 0, reservePrice, block.timestamp + startDelay, 0, duration);
        Auction memory retAuction = auction;
        uint256 prevSenderBalance = chris.balance;
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice + bidExtra);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(0), reservePrice, block.timestamp + startDelay, duration, true
        );

        // test prior to auction open
        if (startDelay > 0) {
            vm.expectRevert(AuctionNotOpen.selector);
            vm.prank(chris);
            auctionHouse.bid(address(nft), 1, reservePrice);
            vm.warp(auction.auctionOpenTime);
        }

        // kick off auction
        auction.highestBid = reservePrice + bidExtra;
        auction.highestBidder = chris;
        auction.startTime = block.timestamp;
        auction.duration = duration > 900 ? duration : 900;
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(chris, address(nft), 1, auction);
        vm.prank(chris);
        auctionHouse.bid{value: reservePrice + bidExtra + fee}(address(nft), 1, reservePrice + bidExtra);
        assert(prevSenderBalance - chris.balance == reservePrice + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == reservePrice + bidExtra + fee);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = david;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(david, address(nft), 1, auction);
        vm.prank(david);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - david.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(chris.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = bsy;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(bsy, address(nft), 1, auction);
        vm.prank(bsy);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - bsy.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(david.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to within 15 minutes
        vm.warp(auction.startTime + auction.duration - 10);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = anon;
        auction.duration = retAuction.duration + 890;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(anon, address(nft), 1, auction);
        vm.prank(anon);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - anon.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(bsy.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to end
        vm.warp(auction.startTime + auction.duration + 1);
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 500 ether}(address(nft), 1, 500 ether);

        // settle
        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), 1, auction);
        auctionHouse.settleAuction(address(nft), 1);
        assert(receiver.balance == nextBid + bidExtra);
        assert(tl.balance == fee);
        assert(address(auctionHouse).balance == initAhBalance);
    }

    /// @dev test bid & settle with erc20 - reserve auction
    function test_bidERC20_reserveAuction(uint256 reservePrice, uint256 startDelay, uint256 duration, uint256 bidExtra)
        public
    {
        // limit fuzz variables
        if (reservePrice > 500 ether) {
            reservePrice = reservePrice % 500 ether;
        }
        if (startDelay > 300 days) {
            startDelay = startDelay % 300 days;
        }
        if (duration > 300 days) {
            duration = duration % 300 days;
        }
        if (bidExtra > 200 ether) {
            bidExtra = bidExtra % 200 ether;
        }

        // initial variables
        uint256 initAhBalance = coin.balanceOf(address(auctionHouse));
        Auction memory auction = Auction(
            ben, receiver, address(coin), address(0), 0, reservePrice, block.timestamp + startDelay, 0, duration
        );
        Auction memory retAuction = auction;
        uint256 prevSenderBalance = coin.balanceOf(chris);
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice + bidExtra);

        // approve erc20 for all bidders
        vm.prank(ben);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(chris);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(david);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(anon);
        coin.approve(address(auctionHouse), 10000 ether);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(coin), reservePrice, block.timestamp + startDelay, duration, true
        );

        // test prior to auction open
        if (startDelay > 0) {
            vm.expectRevert(AuctionNotOpen.selector);
            vm.prank(chris);
            auctionHouse.bid(address(nft), 1, reservePrice);
            vm.warp(auction.auctionOpenTime);
        }

        // kick off auction
        auction.highestBid = reservePrice + bidExtra;
        auction.highestBidder = chris;
        auction.startTime = block.timestamp;
        auction.duration = duration > 900 ? duration : 900;
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(chris, address(nft), 1, auction);
        vm.prank(chris);
        auctionHouse.bid(address(nft), 1, reservePrice + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(chris) == reservePrice + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == reservePrice + bidExtra + fee);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = david;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(david, address(nft), 1, auction);
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(david) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(chris) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = bsy;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(bsy, address(nft), 1, auction);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(bsy) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(david) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to within 15 minutes
        vm.warp(auction.startTime + auction.duration - 10);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = anon;
        auction.duration = retAuction.duration + 890;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(anon, address(nft), 1, auction);
        vm.prank(anon);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(anon) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(bsy) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to end
        vm.warp(auction.startTime + auction.duration + 1);
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 500 ether}(address(nft), 1, 500 ether);

        // settle
        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), 1, auction);
        auctionHouse.settleAuction(address(nft), 1);
        assert(coin.balanceOf(receiver) == nextBid + bidExtra);
        assert(coin.balanceOf(tl) == fee);
        assert(coin.balanceOf(address(auctionHouse)) == initAhBalance);
    }

    /// @dev test bid & settle with eth - reserve auction
    function test_bidEth_scheduledAuction(uint256 reservePrice, uint256 startDelay, uint256 duration, uint256 bidExtra)
        public
    {
        // limit fuzz variables
        if (reservePrice > 500 ether) {
            reservePrice = reservePrice % 500 ether;
        }
        if (startDelay > 300 days) {
            startDelay = startDelay % 300 days;
        }
        if (duration > 300 days) {
            duration = duration % 300 days;
        }
        if (bidExtra > 200 ether) {
            bidExtra = bidExtra % 200 ether;
        }

        // initial variables
        uint256 initAhBalance = address(auctionHouse).balance;
        Auction memory auction = Auction(
            ben,
            receiver,
            address(0),
            address(0),
            0,
            reservePrice,
            block.timestamp + startDelay,
            block.timestamp + startDelay,
            duration
        );
        Auction memory retAuction = auction;
        uint256 prevSenderBalance = chris.balance;
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice + bidExtra);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(0), reservePrice, block.timestamp + startDelay, duration, false
        );

        // test prior to auction open
        if (startDelay > 0) {
            vm.expectRevert(AuctionNotOpen.selector);
            vm.prank(chris);
            auctionHouse.bid(address(nft), 1, reservePrice);
            vm.warp(auction.auctionOpenTime);
        }

        // kick off auction
        auction.highestBid = reservePrice + bidExtra;
        auction.highestBidder = chris;
        auction.duration = duration > 900 ? duration : 900;
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(chris, address(nft), 1, auction);
        vm.prank(chris);
        auctionHouse.bid{value: reservePrice + bidExtra + fee}(address(nft), 1, reservePrice + bidExtra);
        assert(prevSenderBalance - chris.balance == reservePrice + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == reservePrice + bidExtra + fee);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = david;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(david, address(nft), 1, auction);
        vm.prank(david);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - david.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(chris.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = bsy;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(bsy, address(nft), 1, auction);
        vm.prank(bsy);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - bsy.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(david.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to within 15 minutes
        vm.warp(auction.startTime + auction.duration - 10);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = anon;
        auction.duration = retAuction.duration + 890;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(anon, address(nft), 1, auction);
        vm.prank(anon);
        auctionHouse.bid{value: nextBid + bidExtra + fee}(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - anon.balance == nextBid + bidExtra + fee);
        assert(address(auctionHouse).balance - initAhBalance == nextBid + bidExtra + fee);
        assert(bsy.balance == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to end
        vm.warp(auction.startTime + auction.duration + 1);
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 500 ether}(address(nft), 1, 500 ether);

        // settle
        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), 1, auction);
        auctionHouse.settleAuction(address(nft), 1);
        assert(receiver.balance == nextBid + bidExtra);
        assert(tl.balance == fee);
        assert(address(auctionHouse).balance == initAhBalance);
    }

    /// @dev test bid & settle with erc20 - scheduled auction
    function test_bidERC20_scheduledAuction(
        uint256 reservePrice,
        uint256 startDelay,
        uint256 duration,
        uint256 bidExtra
    ) public {
        // limit fuzz variables
        if (reservePrice > 500 ether) {
            reservePrice = reservePrice % 500 ether;
        }
        if (startDelay > 300 days) {
            startDelay = startDelay % 300 days;
        }
        if (duration > 300 days) {
            duration = duration % 300 days;
        }
        if (bidExtra > 200 ether) {
            bidExtra = bidExtra % 200 ether;
        }

        // initial variables
        uint256 initAhBalance = coin.balanceOf(address(auctionHouse));
        Auction memory auction = Auction(
            ben,
            receiver,
            address(coin),
            address(0),
            0,
            reservePrice,
            block.timestamp + startDelay,
            block.timestamp + startDelay,
            duration
        );
        Auction memory retAuction = auction;
        uint256 prevSenderBalance = coin.balanceOf(chris);
        uint256 nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        uint256 fee = auctionHouse.calcProtocolFee(reservePrice + bidExtra);

        // approve erc20 for all bidders
        vm.prank(ben);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(chris);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(david);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(bsy);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.prank(anon);
        coin.approve(address(auctionHouse), 10000 ether);

        // configure auction
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.expectEmit(true, true, true, true);
        emit AuctionConfigured(ben, address(nft), 1, auction);
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, receiver, address(coin), reservePrice, block.timestamp + startDelay, duration, false
        );

        // test prior to auction open
        if (startDelay > 0) {
            vm.expectRevert(AuctionNotOpen.selector);
            vm.prank(chris);
            auctionHouse.bid(address(nft), 1, reservePrice);
            vm.warp(auction.auctionOpenTime);
        }

        // kick off auction
        auction.highestBid = reservePrice + bidExtra;
        auction.highestBidder = chris;
        auction.duration = duration > 900 ? duration : 900;
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(chris, address(nft), 1, auction);
        vm.prank(chris);
        auctionHouse.bid(address(nft), 1, reservePrice + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(chris) == reservePrice + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == reservePrice + bidExtra + fee);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = david;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(david, address(nft), 1, auction);
        vm.prank(david);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(david) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(chris) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = bsy;
        auction.duration = duration > 900 ? duration : 900;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(bsy, address(nft), 1, auction);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(bsy) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(david) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to within 15 minutes
        vm.warp(auction.startTime + auction.duration - 10);

        // bid
        nextBid = auctionHouse.calcNextMinBid(address(nft), 1);
        auction.highestBid = nextBid + bidExtra;
        auction.highestBidder = anon;
        auction.duration = retAuction.duration + 890;
        fee = auctionHouse.calcProtocolFee(auction.highestBid);
        vm.expectEmit(true, true, true, true);
        emit AuctionBid(anon, address(nft), 1, auction);
        vm.prank(anon);
        auctionHouse.bid(address(nft), 1, nextBid + bidExtra);
        assert(prevSenderBalance - coin.balanceOf(anon) == nextBid + bidExtra + fee);
        assert(coin.balanceOf(address(auctionHouse)) - initAhBalance == nextBid + bidExtra + fee);
        assert(coin.balanceOf(bsy) == 10000 ether);
        retAuction = auctionHouse.getAuction(address(nft), 1);
        assert(retAuction.highestBidder == auction.highestBidder);
        assert(retAuction.highestBid == auction.highestBid);
        assert(retAuction.startTime == auction.startTime);
        assert(retAuction.duration == auction.duration);

        // warp to end
        vm.warp(auction.startTime + auction.duration + 1);
        vm.expectRevert(AuctionEnded.selector);
        vm.prank(bsy);
        auctionHouse.bid{value: 500 ether}(address(nft), 1, 500 ether);

        // settle
        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(this), address(nft), 1, auction);
        auctionHouse.settleAuction(address(nft), 1);
        assert(coin.balanceOf(receiver) == nextBid + bidExtra);
        assert(coin.balanceOf(tl) == fee);
        assert(coin.balanceOf(address(auctionHouse)) == initAhBalance);
    }

    /// @dev test two auctions at the same time
    function test_twoAuctionsSimultaneously() public {
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, true);
        auctionHouse.configureAuction(address(nft), 2, ben, address(0), 0, block.timestamp, 24 hours, true);
        vm.stopPrank();

        // kick off first auction and ensure nothing happened with the second auction
        vm.prank(chris);
        auctionHouse.bid(address(nft), 1, 0);
        Auction memory auctionOne = auctionHouse.getAuction(address(nft), 1);
        Auction memory auctionTwo = auctionHouse.getAuction(address(nft), 2);
        assert(auctionOne.startTime == block.timestamp);
        assert(auctionTwo.startTime == 0);

        // kick off second auction and ensure nothing happened with the first auction
        vm.prank(bsy);
        auctionHouse.bid{value: 1}(address(nft), 2, 1);
        auctionOne = auctionHouse.getAuction(address(nft), 1);
        auctionTwo = auctionHouse.getAuction(address(nft), 2);
        assert(auctionOne.highestBid == 0);
        assert(auctionOne.highestBidder == chris);
        assert(auctionTwo.startTime == block.timestamp);
        assert(auctionTwo.highestBid == 1);
        assert(auctionTwo.highestBidder == bsy);
    }

    /// @dev test configure sale
    function test_configureSale(address hacker, address payoutReceiver, bool useEth, uint256 price, uint256 startTime)
        public
    {
        // limit fuzz inputs
        vm.assume(hacker != ben && hacker != address(0));
        vm.assume(payoutReceiver != address(0));
        if (price > 1000 ether) {
            price = price % 1000 ether;
        }

        address currencyAddress = useEth ? address(0) : address(coin);

        // not token owner
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);

        // auction house not approved
        vm.expectRevert(AuctionHouseNotApproved.selector);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);

        // approve token auction house - fail
        vm.prank(ben);
        nft.approve(address(auctionHouse), 1);
        vm.expectRevert(AuctionHouseNotApproved.selector);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);

        // approve auction house for all
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);

        // zero address payout receiver
        vm.expectRevert(PayoutToZeroAddress.selector);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, address(0), currencyAddress, price, startTime);

        // configure sale
        Sale memory sale = Sale(ben, payoutReceiver, currencyAddress, price, startTime);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(ben, address(nft), 1, sale);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);
        sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == ben);
        assert(sale.payoutReceiver == payoutReceiver);
        assert(sale.currencyAddress == currencyAddress);
        assert(sale.price == price);
        assert(sale.saleOpenTime == startTime);

        // override sale
        sale.price = price + 1;
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(ben, address(nft), 1, sale);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price + 1, startTime);
        sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == ben);
        assert(sale.payoutReceiver == payoutReceiver);
        assert(sale.currencyAddress == currencyAddress);
        assert(sale.price == price + 1);
        assert(sale.saleOpenTime == startTime);

        // transfer nft and configure sale
        sale.price = price;
        sale.seller = chris;
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        vm.prank(chris);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(chris, address(nft), 1, sale);
        vm.prank(chris);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);
        sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == chris);
        assert(sale.payoutReceiver == payoutReceiver);
        assert(sale.currencyAddress == currencyAddress);
        assert(sale.price == price);
        assert(sale.saleOpenTime == startTime);

        // transfer back to ben
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);

        // cancel sale
        vm.prank(ben);
        auctionHouse.cancelSale(address(nft), 1);

        // configure auction & start
        vm.prank(ben);
        auctionHouse.configureAuction(
            address(nft), 1, payoutReceiver, currencyAddress, 0, block.timestamp, 24 hours, true
        );
        vm.prank(chris);
        auctionHouse.bid(address(nft), 1, 0);
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, payoutReceiver, currencyAddress, price, startTime);
    }

    /// @dev test cancel sale
    function test_cancelSale(address hacker) public {
        // limit fuzz input
        vm.assume(hacker != ben && hacker != chris && hacker != address(0));

        // cancel nonexistent auction (should pass but waste of gas)
        vm.prank(ben);
        auctionHouse.cancelSale(address(nft), 1);

        // setup sale
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);

        // not token owner
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.cancelSale(address(nft), 1);

        // successfully cancel sale
        vm.expectEmit(true, true, true, false);
        emit SaleCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelSale(address(nft), 1);

        // setup sale again
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);

        // transfer token and still be able to cancel if seller calls
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        vm.expectRevert(CallerNotTokenOwner.selector);
        vm.prank(hacker);
        auctionHouse.cancelSale(address(nft), 1);
        vm.expectEmit(true, true, true, false);
        emit SaleCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelSale(address(nft), 1);

        // setup sale again
        vm.prank(chris);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(chris);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);

        // transfer token and the new owner can cancel the auction
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);
        vm.expectEmit(true, true, true, false);
        emit SaleCanceled(ben, address(nft), 1);
        vm.prank(ben);
        auctionHouse.cancelSale(address(nft), 1);
    }

    /// @dev test buy now with malicious nft
    function test_buyNowMaliciousNft() public {
        // malicious nft
        MaliciousERC721 mnft = new MaliciousERC721();
        mnft.mint(ben);
        mnft.setBeMalicious(true);

        // configure sale
        vm.prank(ben);
        mnft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureSale(address(mnft), 1, receiver, address(0), 1 ether, block.timestamp);

        // revert on purchase
        vm.prank(chris);
        vm.expectRevert(NftNotTransferred.selector);
        auctionHouse.buyNow{value: 1.01 ether}(address(mnft), 1);
    }

    /// @dev test buy now eth errors
    function test_buyNowEthErrors() public {
        // sale not configured
        vm.expectRevert(SaleNotConfigured.selector);
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);

        // configure sale
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, receiver, address(0), 1 ether, block.timestamp + 1000);

        // sale not open
        vm.expectRevert(SaleNotOpen.selector);
        vm.prank(chris);
        auctionHouse.buyNow{value: 1.01 ether}(address(nft), 1);

        // warp
        vm.warp(block.timestamp + 1000);

        // nft not owned by the seller
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        uint256 fee = auctionHouse.calcProtocolFee(1 ether);
        vm.expectRevert(NftNotOwnedBySeller.selector);
        vm.prank(bsy);
        auctionHouse.buyNow{value: 1 ether + fee}(address(nft), 1);

        // return nft
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);

        // not enough eth attached
        vm.expectRevert(InsufficientMsgValue.selector);
        vm.prank(chris);
        auctionHouse.buyNow{value: 1 ether}(address(nft), 1);
    }

    /// @dev test buy now erc20 errors
    function test_buyNowERC20Errors() public {
        // sale not configured
        vm.expectRevert(SaleNotConfigured.selector);
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);

        // configure sale
        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, receiver, address(coin), 1 ether, block.timestamp + 1000);

        // sale not open
        vm.expectRevert(SaleNotOpen.selector);
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);

        // warp
        vm.warp(block.timestamp + 1000);

        // nft not owned by the seller
        vm.prank(ben);
        nft.transferFrom(ben, chris, 1);
        uint256 fee = auctionHouse.calcProtocolFee(1 ether);
        vm.expectRevert(NftNotOwnedBySeller.selector);
        vm.prank(bsy);
        auctionHouse.buyNow{value: 1 ether + fee}(address(nft), 1);

        // return nft
        vm.prank(chris);
        nft.transferFrom(chris, ben, 1);

        // not enough erc20 approval attached
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(auctionHouse), 0, 1 ether + fee
            )
        );
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);

        // approve coin
        vm.prank(chris);
        coin.approve(address(auctionHouse), 10 ether);

        // not enough erc20 balance
        vm.prank(chris);
        coin.transfer(bsy, 10000 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 1 ether + fee));
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);
    }

    /// @dev test refund buy now eth
    function test_buyNowRefundEth(uint256 price, uint256 extra) public {
        if (price > 500 ether) {
            price = price % 500 ether;
        }
        if (extra > 500 ether) {
            extra = extra % 500 ether;
        }

        // configure sale
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureSale(address(nft), 1, receiver, address(0), price, block.timestamp);
        vm.stopPrank();

        // buy now with extra and ensure that only the price + fee is taken with the rest refunded
        Sale memory sale = Sale(ben, receiver, address(0), price, block.timestamp);
        uint256 initReceiverBalance = receiver.balance;
        uint256 initTlBalance = tl.balance;
        uint256 initChrisBlance = chris.balance;
        uint256 fee = auctionHouse.calcProtocolFee(price);
        vm.expectEmit(true, true, true, true);
        emit SaleFulfilled(chris, address(nft), 1, sale);
        vm.prank(chris);
        auctionHouse.buyNow{value: price + extra + fee}(address(nft), 1);
        assert(nft.ownerOf(1) == chris);
        assert(receiver.balance - initReceiverBalance == price);
        assert(tl.balance - initTlBalance == fee);
        assert(initChrisBlance - chris.balance == price + fee);
        sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == address(0));
        assert(sale.payoutReceiver == address(0));
        assert(sale.currencyAddress == address(0));
        assert(sale.price == 0);
        assert(sale.saleOpenTime == 0);
    }

    /// @dev test refund buy now erc20
    function test_buyNowRefundErc20(uint256 price, uint256 extra) public {
        if (price > 500 ether) {
            price = price % 500 ether;
        }
        if (extra > 500 ether) {
            extra = extra % 500 ether;
        }

        // configure sale
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureSale(address(nft), 1, receiver, address(coin), price, block.timestamp);
        vm.stopPrank();

        // buy now with extra and ensure that only the price + fee is taken with the rest refunded
        Sale memory sale = Sale(ben, receiver, address(coin), price, block.timestamp);
        uint256 initReceiverBalance = coin.balanceOf(receiver);
        uint256 initTlBalance = coin.balanceOf(tl);
        uint256 initChrisBlance = coin.balanceOf(chris);
        uint256 initChrisEthBalance = chris.balance;
        uint256 fee = auctionHouse.calcProtocolFee(price);
        vm.prank(chris);
        coin.approve(address(auctionHouse), 10000 ether);
        vm.expectEmit(true, true, true, true);
        emit SaleFulfilled(chris, address(nft), 1, sale);
        vm.prank(chris);
        auctionHouse.buyNow{value: extra}(address(nft), 1);
        assert(nft.ownerOf(1) == chris);
        assert(coin.balanceOf(receiver) - initReceiverBalance == price);
        assert(coin.balanceOf(tl) - initTlBalance == fee);
        assert(initChrisBlance - coin.balanceOf(chris) == price + fee);
        assert(chris.balance == initChrisEthBalance);
        sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == address(0));
        assert(sale.payoutReceiver == address(0));
        assert(sale.currencyAddress == address(0));
        assert(sale.price == 0);
        assert(sale.saleOpenTime == 0);
    }

    /// @dev test sale and auction live at the same time - bid
    function test_saleClearedOnAuctionBid() public {
        // configure auction and sale
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, true);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);
        vm.stopPrank();

        // kick off auciton and verify the sale is not existent
        vm.prank(chris);
        auctionHouse.bid(address(nft), 1, 0);
        Sale memory sale = auctionHouse.getSale(address(nft), 1);
        assert(sale.seller == address(0));
        assert(sale.payoutReceiver == address(0));
        assert(sale.currencyAddress == address(0));
        assert(sale.price == 0);
        assert(sale.saleOpenTime == 0);
        vm.expectRevert(SaleNotConfigured.selector);
        vm.prank(bsy);
        auctionHouse.buyNow(address(nft), 1);
    }

    /// @dev test sale and auction live at the same time - buy now
    function test_auctionClearedOnSaleFulfilled() public {
        // configure auction and sale
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, true);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);
        vm.stopPrank();

        // buy now and verify the auction is non-existent
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);
        Auction memory auction = auctionHouse.getAuction(address(nft), 1);
        assert(auction.seller == address(0));
        assert(auction.payoutReceiver == address(0));
        assert(auction.currencyAddress == address(0));
        assert(auction.reservePrice == 0);
        assert(auction.auctionOpenTime == 0);
        assert(auction.duration == 0);
        assert(auction.highestBid == 0);
        assert(auction.highestBidder == address(0));
        assert(auction.duration == 0);
        vm.expectRevert(AuctionNotConfigured.selector);
        vm.prank(bsy);
        auctionHouse.bid(address(nft), 1, 0);
    }

    /// @dev test two sales at the same time
    function test_twoSaleSimultaneously() public {
        // configure sales
        vm.startPrank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);
        auctionHouse.configureSale(address(nft), 2, ben, address(0), 0, block.timestamp);
        vm.stopPrank();

        // buy first sale and ensure the second sale is still active
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 1);
        Sale memory saleOne = auctionHouse.getSale(address(nft), 1);
        Sale memory saleTwo = auctionHouse.getSale(address(nft), 2);
        assert(saleOne.seller == address(0));
        assert(saleOne.payoutReceiver == address(0));
        assert(saleOne.currencyAddress == address(0));
        assert(saleOne.price == 0);
        assert(saleOne.saleOpenTime == 0);
        assert(saleTwo.seller == ben);
        assert(saleTwo.payoutReceiver == ben);
        assert(saleTwo.currencyAddress == address(0));
        assert(saleTwo.price == 0);
        assert(saleTwo.saleOpenTime == block.timestamp);

        // buy the second one and ensure both sales are inactive
        vm.prank(chris);
        auctionHouse.buyNow(address(nft), 2);
        saleOne = auctionHouse.getSale(address(nft), 1);
        saleTwo = auctionHouse.getSale(address(nft), 2);
        assert(saleOne.seller == address(0));
        assert(saleOne.payoutReceiver == address(0));
        assert(saleOne.currencyAddress == address(0));
        assert(saleOne.price == 0);
        assert(saleOne.saleOpenTime == 0);
        assert(saleTwo.seller == address(0));
        assert(saleTwo.payoutReceiver == address(0));
        assert(saleTwo.currencyAddress == address(0));
        assert(saleTwo.price == 0);
        assert(saleTwo.saleOpenTime == 0);
    }

    function test_sanctions() public {
        address oracle = makeAddr(unicode"sanctions are the best 🫠");
        auctionHouse.setSanctionsOracle(oracle);

        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));

        vm.prank(ben);
        nft.setApprovalForAll(address(auctionHouse), true);

        // test configuration functions
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, false);

        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);

        // configure auction and sale and test bid/buy now
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.prank(ben);
        auctionHouse.configureAuction(address(nft), 1, ben, address(0), 0, block.timestamp, 24 hours, false);

        vm.prank(ben);
        auctionHouse.configureSale(address(nft), 1, ben, address(0), 0, block.timestamp);

        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));

        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        auctionHouse.bid{value: 1 ether}(address(nft), 1, 1 ether);

        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        auctionHouse.buyNow(address(nft), 1);

        vm.clearMockedCalls();
    }
}

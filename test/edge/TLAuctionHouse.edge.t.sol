// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "forge-std-1.9.4/Vm.sol";
import {
    AuditRecoveryNFT,
    AuditHookCurrency,
    AuditCallbackSeller,
    AuditPassivePayee,
    MalformedRoyaltyNFT
} from "test/utils/AuditRecoveryMocks.sol";
import {BlocklistERC20} from "test/utils/BlocklistERC20.sol";
import {TransferHelper} from "src/lib/TransferHelper.sol";
import {Test} from "forge-std-1.9.4/Test.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuard.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {RoyaltyLookup} from "src/helpers/RoyaltyLookup.sol";
import {SanctionsCompliance} from "src/lib/SanctionsCompliance.sol";
import {CurrencyAllowlist} from "src/lib/CurrencyAllowlist.sol";
import {ITLAuctionHouseEvents, ListingType, Listing, ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";
import {GriefingBidder} from "test/utils/Receiver.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockRoyaltyLookup} from "test/utils/MockRoyaltyLookup.sol";
import {MockSanctionsOracle} from "test/utils/MockSanctionsOracle.sol";

/// @dev A receiver that needs substantially more than 100k gas under the local EVM schedule.
contract StorageWritingPayee {
    uint256[12] public receipts;

    receive() external payable {
        for (uint256 i; i < receipts.length; ++i) {
            receipts[i] = msg.value + i;
        }
    }

    function bid(TLAuctionHouse auction, address nft, uint256 tokenId, uint256 listingId) external payable {
        auction.bid{value: msg.value}(nft, tokenId, address(0), msg.value, listingId);
    }

    function claim(TLAuctionHouse auction) external {
        auction.claimFunds(address(0), address(this));
    }
}

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

    function test_observation_renounceDisabled() public {
        address next = makeAddr("nextOwner");
        ah.transferOwnership(next);
        ah.pause(true);
        vm.expectRevert(bytes4(keccak256("OwnershipRenunciationDisabled()")));
        ah.renounceOwnership();
        assertEq(ah.owner(), address(this));
        assertEq(ah.pendingOwner(), next);
        vm.prank(next);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", next));
        ah.renounceOwnership();
        ah.transferOwnership(address(0));
        assertEq(ah.pendingOwner(), address(0));
        ah.transferOwnership(next);
        vm.prank(next);
        ah.acceptOwnership();
        assertEq(ah.owner(), next);
        vm.prank(next);
        ah.pause(false);
    }

    function test_deploymentCodeSize() public {
        assertLe(address(ah).code.length, 24_576, "runtime exceeds EIP-170 deployment limit");
    }

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

    function test_pending_feeWaiverIdentity() public {
        uint256 oldId = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 days);
        ListingConfig memory cfg = _cfg(ListingType.RESERVE_AUCTION, address(0), 1 ether, 1 days, 0);
        vm.prank(seller);
        ah.updateListing(cfg);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.removeProtocolFee(address(nft), TOKEN, oldId);
        uint256 currentId = ah.getListing(address(nft), TOKEN).id;
        assertFalse(ah.getListing(address(nft), TOKEN).zeroProtocolFee);
        ah.removeProtocolFee(address(nft), TOKEN, currentId);
        vm.prank(seller);
        ah.updateListing(cfg);
        assertTrue(ah.getListing(address(nft), TOKEN).zeroProtocolFee);
        vm.prank(seller);
        ah.delist(address(nft), TOKEN);
        vm.prank(seller);
        ah.list(cfg);
        vm.expectRevert(TLAuctionHouse.ListingChanged.selector);
        ah.removeProtocolFee(address(nft), TOKEN, currentId);
        assertFalse(ah.getListing(address(nft), TOKEN).zeroProtocolFee);
    }

    function test_pending_staleClaimRetiredAtomically() public {
        _checkClaimRetirement(bidder2);
    }

    function test_pending_sameOwnerRedepositRetiresClaim() public {
        _checkClaimRetirement(seller);
    }

    function _checkClaimRetirement(address nextSeller) internal {
        AuditRecoveryNFT recovered = new AuditRecoveryNFT();
        recovered.mint(seller, TOKEN);
        ListingConfig memory cfg = _cfg(ListingType.RESERVE_AUCTION, address(0), 1 ether, 1 hours, 0);
        cfg.nftAddress = address(recovered);
        vm.startPrank(seller);
        recovered.setApprovalForAll(address(ah), true);
        ah.list(cfg);
        vm.stopPrank();
        uint256 lid = ah.getListing(address(recovered), TOKEN).id;
        vm.prank(bidder1);
        ah.bid{value: 1 ether}(address(recovered), TOKEN, address(0), 1 ether, lid);
        Listing memory l = ah.getListing(address(recovered), TOKEN);
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);
        vm.prank(bidder1);
        ah.cancelUnsettledAuction(address(recovered), TOKEN);
        recovered.recover(nextSeller, TOKEN);
        vm.prank(nextSeller);
        recovered.setApprovalForAll(address(ah), true);
        recovered.setSkipTransfer(true);
        vm.prank(nextSeller);
        vm.expectRevert(TLAuctionHouse.NftTransferFailed.selector);
        ah.list(cfg);
        assertEq(ah.claimableNft(address(recovered), TOKEN), seller);
        recovered.setSkipTransfer(false);
        // Failure of a later batch item rolls back an otherwise successful deposit and retirement.
        ListingConfig[] memory configs = new ListingConfig[](2);
        configs[0] = cfg;
        configs[1] = cfg;
        vm.prank(nextSeller);
        vm.expectRevert(TLAuctionHouse.AlreadyListed.selector);
        ah.batchList(configs);
        assertEq(ah.claimableNft(address(recovered), TOKEN), seller);
        assertEq(recovered.ownerOf(TOKEN), nextSeller);
        vm.prank(nextSeller);
        vm.expectEmit(true, true, true, true, address(ah));
        emit ITLAuctionHouseEvents.NftClaimRetired(address(recovered), TOKEN, seller, nextSeller);
        ah.list(cfg);
        assertEq(ah.claimableNft(address(recovered), TOKEN), address(0));
        assertEq(ah.claimableFunds(bidder1, address(0)), 1 ether);
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        ah.claimNft(address(recovered), TOKEN, seller);
        assertEq(recovered.ownerOf(TOKEN), address(ah));
        vm.prank(nextSeller);
        ah.delist(address(recovered), TOKEN);
        assertEq(recovered.ownerOf(TOKEN), nextSeller);
    }

    function test_pending_permissionlessRetry() public {
        AuditPassivePayee payee = new AuditPassivePayee(ah);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.payoutReceiver = address(payee);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        vm.prank(bidder1);
        ah.buyNow{value: 1 ether}(address(nft), TOKEN, bidder1, address(0), 1 ether, lid);
        assertEq(ah.claimableFunds(address(payee), address(0)), 0.89 ether);
        vm.expectRevert(TransferHelper.ETHTransferFailed.selector);
        ah.retryPayout(address(payee), address(0));
        assertEq(ah.claimableFunds(address(payee), address(0)), 0.89 ether);
        oracle.setSanctioned(address(payee), true);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        ah.retryPayout(address(payee), address(0));
        oracle.setSanctioned(address(payee), false);
        vm.mockCallRevert(
            address(oracle),
            abi.encodeWithSignature("isSanctioned(address)", address(payee)),
            abi.encodeWithSignature("Error(string)", "oracle failed")
        );
        vm.expectRevert("oracle failed");
        ah.retryPayout(address(payee), address(0));
        assertEq(ah.claimableFunds(address(payee), address(0)), 0.89 ether);
        vm.clearMockedCalls();
        payee.setReject(false);
        payee.setTryReentry();
        ah.pause(true);
        uint256 callerBalance = bidder2.balance;
        vm.prank(bidder2);
        ah.retryPayout(address(payee), address(0));
        assertEq(address(payee).balance, 0.89 ether);
        assertEq(bidder2.balance, callerBalance);
        assertFalse(payee.reentrySucceeded());
        assertEq(ah.claimableFunds(address(payee), address(0)), 0);
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        ah.retryPayout(address(payee), address(0));
    }

    function test_pending_retryErc20AfterIssuerUnblocks() public {
        BlocklistERC20 currency = new BlocklistERC20(address(this));
        ah.setCurrencyAllowed(address(currency), true);
        currency.setBlocked(payout, true);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(currency), 0, 0, 1 ether);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        currency.transfer(bidder1, 1 ether);
        vm.startPrank(bidder1);
        currency.approve(address(ah), 1 ether);
        ah.buyNow(address(nft), TOKEN, bidder1, address(currency), 1 ether, lid);
        vm.stopPrank();
        vm.expectRevert("blocked");
        ah.retryPayout(payout, address(currency));
        assertEq(ah.claimableFunds(payout, address(currency)), 0.89 ether);
        currency.setBlocked(payout, false);
        ah.setCurrencyAllowed(address(currency), false);
        ah.retryPayout(payout, address(currency));
        assertEq(currency.balanceOf(payout), 0.89 ether);
        assertEq(ah.claimableFunds(payout, address(currency)), 0);
    }

    /// @dev OBS-014: `updatePayoutReceiver` is `nonReentrant`, so a callback during an NFT transfer cannot change the
    ///      listing mid-call. The listing reverts atomically, and a normal listing's event matches storage.
    function test_callbackPayoutUpdate_blockedDuringListing() public {
        AuditRecoveryNFT token = new AuditRecoveryNFT();
        AuditCallbackSeller callbackSeller = new AuditCallbackSeller(ah, address(token), bidder2);
        token.mint(address(callbackSeller), 1);
        ListingConfig memory cfg = _cfg(ListingType.RESERVE_AUCTION, address(0), 1 ether, 1 hours, 0);
        cfg.nftAddress = address(token);
        token.setHook(address(callbackSeller));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        callbackSeller.list(cfg);
        assertEq(uint8(ah.getListing(address(token), 1).type_), uint8(ListingType.NOT_CONFIGURED));
        assertEq(token.ownerOf(1), address(callbackSeller));

        token.setHook(address(0));
        vm.recordLogs();
        callbackSeller.list(cfg);
        _assertListingEvent(ITLAuctionHouseEvents.ListingConfigured.selector, address(token), payout);
    }

    /// @dev OBS-014: a refunded bidder that is also the seller cannot change the payout receiver from its refund
    ///      callback. The refund is credited instead, and the bid event matches storage.
    function test_callbackPayoutUpdate_blockedDuringRefund() public {
        AuditRecoveryNFT token = new AuditRecoveryNFT();
        AuditCallbackSeller callbackSeller = new AuditCallbackSeller(ah, address(token), bidder2);
        token.mint(address(callbackSeller), 1);
        ListingConfig memory cfg = _cfg(ListingType.RESERVE_AUCTION, address(0), 1 ether, 1 hours, 0);
        cfg.nftAddress = address(token);
        callbackSeller.list(cfg);
        uint256 lid = ah.getListing(address(token), 1).id;
        vm.deal(address(this), 1 ether);
        callbackSeller.bid{value: 1 ether}(lid);
        vm.recordLogs();
        vm.prank(bidder1);
        ah.bid{value: 2 ether}(address(token), 1, address(0), 2 ether, lid);
        _assertListingEvent(ITLAuctionHouseEvents.AuctionBid.selector, address(token), payout);
        assertEq(ah.claimableFunds(address(callbackSeller), address(0)), 1 ether);
    }

    /// @dev OBS-014: a currency callback cannot change the payout receiver during a top-up; the top-up reverts
    ///      atomically, and a normal top-up's event matches storage.
    function test_callbackPayoutUpdate_blockedDuringTopUp() public {
        AuditRecoveryNFT token = new AuditRecoveryNFT();
        AuditCallbackSeller callbackSeller = new AuditCallbackSeller(ah, address(token), bidder2);
        AuditHookCurrency currency = new AuditHookCurrency(bidder1);
        ah.setCurrencyAllowed(address(currency), true);
        token.mint(address(callbackSeller), 1);
        ListingConfig memory cfg = _cfg(ListingType.RESERVE_AUCTION, address(currency), 1 ether, 1 hours, 0);
        cfg.nftAddress = address(token);
        callbackSeller.list(cfg);
        uint256 lid = ah.getListing(address(token), 1).id;
        vm.startPrank(bidder1);
        currency.approve(address(ah), 10 ether);
        ah.bid(address(token), 1, address(currency), 1 ether, lid);
        vm.stopPrank();

        currency.setHook(address(callbackSeller));
        vm.prank(bidder1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        ah.topUpBid(address(token), 1, 1 ether, lid);
        assertEq(ah.getListing(address(token), 1).highestBid, 1 ether);

        currency.setHook(address(0));
        vm.recordLogs();
        vm.prank(bidder1);
        ah.topUpBid(address(token), 1, 1 ether, lid);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(ah) && logs[i].topics[0] == ITLAuctionHouseEvents.AuctionBidToppedUp.selector
            ) {
                (uint256 amount, Listing memory emitted) = abi.decode(logs[i].data, (uint256, Listing));
                assertEq(amount, 1 ether);
                assertEq(abi.encode(emitted), abi.encode(ah.getListing(address(token), 1)));
                assertEq(emitted.payoutReceiver, payout);
                found = true;
            }
        }
        assertTrue(found);
    }

    function _assertListingEvent(bytes32 signature, address token, address expectedPayout) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(ah) && logs[i].topics[0] == signature) {
                Listing memory emitted = abi.decode(logs[i].data, (Listing));
                assertEq(abi.encode(emitted), abi.encode(ah.getListing(token, 1)));
                assertEq(emitted.payoutReceiver, expectedPayout);
                found = true;
            }
        }
        assertTrue(found, "listing event missing");
    }

    /// @dev End-to-end royalty resolution through the real `RoyaltyLookup`, with a scriptable engine:
    ///      0 engine reverts, 1 auction-house lookup unset, 2 empty schedule, 3 zero amount, 4 mismatched arrays,
    ///      5 payable engine schedule, 6 engine and NFT both revert, 7 nonzero amount only to the zero address
    function testFuzz_royaltyResolutionModes(uint8 mode) public {
        mode = uint8(bound(mode, 0, 7));
        RoyaltyLookup helper = new RoyaltyLookup(address(this));
        MockRoyaltyLookup engine = new MockRoyaltyLookup(); // same selectors as IRoyaltyEngineV1
        helper.setRoyaltyEngine(address(engine));
        ah.setRoyaltyLookup(address(helper));
        if (mode == 0 || mode == 6) {
            engine.setShouldRevert(true);
        } else if (mode == 1) {
            ah.setRoyaltyLookup(address(0));
        } else {
            address payable[] memory r = new address payable[](mode == 2 ? 0 : 1);
            uint256[] memory a = new uint256[](mode == 4 ? 0 : r.length);
            if (r.length != 0 && mode != 7) r[0] = payable(royalty0);
            if (mode == 5 || mode == 7) a[0] = 500;
            engine.setSchedule(r, a, true);
        }
        if (mode == 6) {
            vm.mockCallRevert(
                address(nft), abi.encodeWithSignature("royaltyInfo(uint256,uint256)", TOKEN, 1 ether), "unsupported"
            );
        }
        (address payable[] memory r, uint256[] memory a) = ah.getRoyalty(address(nft), TOKEN, 1 ether);
        uint256 royalty = mode == 1 || mode == 6 ? 0 : mode == 5 ? 0.05 ether : 0.1 ether;
        if (royalty == 0) {
            assertEq(a.length, 0);
        } else {
            assertEq(a[0], royalty);
            assertEq(r[0], mode == 5 ? royalty0 : creator);
        }
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 hours);
        _bid(bidder1, 1 ether, lid);
        _settle();
        assertEq(creator.balance + royalty0.balance, royalty);
        assertEq(payout.balance, 0.99 ether - royalty);
    }

    function test_filteredEngineRoyaltyWithLatePayeeFallsBackToERC2981() public {
        RoyaltyLookup helper = new RoyaltyLookup(address(this));
        MockRoyaltyLookup engine = new MockRoyaltyLookup();
        helper.setRoyaltyEngine(address(engine));
        ah.setRoyaltyLookup(address(helper));

        uint256 length = ah.MAX_ROYALTY_RECIPIENTS() + 1;
        address payable[] memory recipients = new address payable[](length);
        uint256[] memory amounts = new uint256[](length);
        recipients[0] = payable(address(ah));
        amounts[0] = 500;
        recipients[length - 1] = payable(royalty0);
        amounts[length - 1] = 500;
        engine.setSchedule(recipients, amounts, true);

        (recipients, amounts) = ah.getRoyalty(address(nft), TOKEN, 1 ether);
        assertEq(recipients.length, 1);
        assertEq(recipients[0], creator);
        assertEq(amounts[0], 0.1 ether);

        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 hours);
        _bid(bidder1, 1 ether, lid);
        _settle();

        assertEq(creator.balance, 0.1 ether);
        assertEq(royalty0.balance, 0);
        assertEq(payout.balance, 0.89 ether);
    }

    /// @dev Malformed direct `royaltyInfo` responses revert the helper, which the auction house catches: the sale
    ///      completes with no royalty instead of reverting
    function testFuzz_malformedRoyaltyResponsesDoNotBlockSales(uint8 mode, bool auction) public {
        mode = uint8(bound(mode, 0, 3));
        ah.setRoyaltyLookup(address(new RoyaltyLookup(address(this))));
        MalformedRoyaltyNFT token = new MalformedRoyaltyNFT();
        token.setMode(mode);
        token.mint(seller, 1);
        vm.prank(seller);
        token.setApprovalForAll(address(ah), true);

        uint256 royalty = mode == 3 ? 0.1 ether : 0;
        (address payable[] memory r, uint256[] memory a) = ah.getRoyalty(address(token), 1, 1 ether);
        assertEq(r.length, mode == 3 ? 1 : 0);
        if (mode == 3) {
            assertEq(r[0], address(0xBEEF));
            assertEq(a[0], royalty);
        }

        ListingConfig memory cfg = auction
            ? _cfg(ListingType.RESERVE_AUCTION, address(0), 1 ether, 1 hours, 0)
            : _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.nftAddress = address(token);
        cfg.tokenId = 1;
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(token), 1).id;
        if (auction) {
            vm.prank(bidder1);
            ah.bid{value: 1 ether}(address(token), 1, address(0), 1 ether, lid);
            vm.warp(block.timestamp + 1 hours + 1);
            ah.settleAuction(address(token), 1);
        } else {
            vm.prank(bidder1);
            ah.buyNow{value: 1 ether}(address(token), 1, bidder1, address(0), 1 ether, lid);
        }
        assertEq(token.ownerOf(1), bidder1);
        assertEq(address(0xBEEF).balance, royalty);
        assertEq(payout.balance, 0.99 ether - royalty);
    }

    /// @dev An unset royalty lookup disables royalties without consulting the NFT
    function test_unsetRoyaltyLookupDisablesRoyalties() public {
        ah.setRoyaltyLookup(address(0));
        (address payable[] memory r,) = ah.getRoyalty(address(nft), TOKEN, 1 ether);
        assertEq(r.length, 0);
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 hours);
        _bid(bidder1, 1 ether, lid);
        _settle();
        assertEq(creator.balance, 0);
        assertEq(payout.balance, 0.99 ether);
    }

    function testFuzz_payoutGasLimit_ownerConfiguration(uint256 newLimit) public {
        newLimit = bound(newLimit, 1, type(uint256).max);
        assertEq(ah.payoutGasLimit(), 1e5);
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", seller));
        ah.setPayoutGasLimit(newLimit);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutGasLimit.selector);
        ah.setPayoutGasLimit(0);
        assertEq(ah.payoutGasLimit(), 1e5);
        ah.pause(true);
        vm.expectEmit(false, false, false, true, address(ah));
        emit ITLAuctionHouseEvents.PayoutGasLimitUpdated(1e5, newLimit);
        ah.setPayoutGasLimit(newLimit);
        assertEq(ah.payoutGasLimit(), newLimit);
        vm.expectEmit(false, false, false, true, address(ah));
        emit ITLAuctionHouseEvents.PayoutGasLimitUpdated(newLimit, 1);
        ah.setPayoutGasLimit(1);
        assertEq(ah.payoutGasLimit(), 1);
    }

    function test_payoutGasLimit_lowCreditsAndExplicitClaimUncapped() public {
        StorageWritingPayee payee = new StorageWritingPayee();
        ah.setPayoutGasLimit(100_000);
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 hours);
        vm.prank(seller);
        ah.updatePayoutReceiver(address(nft), TOKEN, address(payee));
        _bid(bidder1, 1 ether, lid);
        _settle();
        assertEq(nft.ownerOf(TOKEN), bidder1);
        assertEq(address(payee).balance, 0);
        assertEq(ah.claimableFunds(address(payee), address(0)), 0.89 ether);
        assertEq(payee.receipts(0), 0);
        assertEq(feeReceiver.balance, 0.01 ether);
        assertEq(royalty0.balance, 0.1 ether);
        ah.setPayoutGasLimit(1);
        ah.pause(true);
        payee.claim(ah);
        assertEq(address(payee).balance, 0.89 ether);
        assertEq(payee.receipts(11), 0.89 ether + 11);
        assertEq(ah.claimableFunds(address(payee), address(0)), 0);
        vm.expectRevert(TLAuctionHouse.NothingToClaim.selector);
        payee.claim(ah);
    }

    function test_payoutGasLimit_refundTracksUpdatedAllowance() public {
        StorageWritingPayee payee = new StorageWritingPayee();
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 1 ether, 1 hours);
        vm.deal(address(this), 3 ether);
        payee.bid{value: 1 ether}(ah, address(nft), TOKEN, lid);
        ah.setPayoutGasLimit(100_000);
        _bid(bidder1, 1.1 ether, lid);
        assertEq(address(payee).balance, 0);
        assertEq(ah.claimableFunds(address(payee), address(0)), 1 ether);
        payee.bid{value: 2 ether}(ah, address(nft), TOKEN, lid);
        ah.setPayoutGasLimit(500_000);
        _bid(bidder2, 3 ether, lid);
        assertEq(address(payee).balance, 2 ether);
        assertEq(payee.receipts(11), 2 ether + 11);
        assertEq(ah.claimableFunds(address(payee), address(0)), 1 ether);
        assertEq(address(ah).balance, 4 ether); // winning bid plus the earlier unpaid refund
    }

    function test_payoutGasLimit_erc20Unaffected() public {
        ah.setPayoutGasLimit(1);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(coin), 0, 0, 1 ether);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        coin.transfer(bidder1, 1 ether);
        vm.startPrank(bidder1);
        coin.approve(address(ah), 1 ether);
        ah.buyNow(address(nft), TOKEN, bidder1, address(coin), 1 ether, lid);
        vm.stopPrank();
        assertEq(nft.ownerOf(TOKEN), bidder1);
        assertEq(coin.balanceOf(feeReceiver), 0.01 ether);
        assertEq(coin.balanceOf(royalty0), 0.1 ether);
        assertEq(coin.balanceOf(payout), 0.89 ether);
        assertEq(coin.balanceOf(address(ah)), 0);
    }

    function test_payoutGasLimit_exhaustingPayeesCreditWithinBudget() public {
        GriefingBidder payee = new GriefingBidder(address(ah));
        ah.setProtocolFeeSettings(address(payee), 100);
        _setRoyalty(royaltyLookup, address(payee), 1_000);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.payoutReceiver = address(payee);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        vm.prank(bidder1);
        ah.buyNow{value: 1 ether, gas: 4_000_000}(address(nft), TOKEN, bidder1, address(0), 1 ether, lid);
        assertEq(nft.ownerOf(TOKEN), bidder1);
        assertEq(address(payee).balance, 0);
        assertEq(ah.claimableFunds(address(payee), address(0)), 1 ether);
        payee.claimFunds(address(0), bidder2);
        assertEq(ah.claimableFunds(address(payee), address(0)), 0);
        assertEq(bidder2.balance, 1_001 ether);
    }

    function test_payoutGasLimit_defaultCreditsStorageWritingReceiver() public {
        StorageWritingPayee payee = new StorageWritingPayee();
        assertEq(ah.payoutGasLimit(), 1e5);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.payoutReceiver = address(payee);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        vm.prank(bidder1);
        ah.buyNow{value: 1 ether}(address(nft), TOKEN, bidder1, address(0), 1 ether, lid);
        assertEq(nft.ownerOf(TOKEN), bidder1);
        assertEq(address(payee).balance, 0);
        assertEq(ah.claimableFunds(address(payee), address(0)), 0.89 ether);
        ah.retryPayout(address(payee), address(0));
        assertEq(address(payee).balance, 0.89 ether);
    }

    function test_payoutGasLimit_raisedAllowancePaysStorageWritingReceivers() public {
        ah.setPayoutGasLimit(1e6);
        StorageWritingPayee protocolPayee = new StorageWritingPayee();
        StorageWritingPayee royaltyPayee = new StorageWritingPayee();
        StorageWritingPayee sellerPayee = new StorageWritingPayee();
        ah.setProtocolFeeSettings(address(protocolPayee), 100);
        _setRoyalty(royaltyLookup, address(royaltyPayee), 1_000);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.payoutReceiver = address(sellerPayee);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        vm.prank(bidder1);
        ah.buyNow{value: 1 ether}(address(nft), TOKEN, bidder1, address(0), 1 ether, lid);
        assertEq(address(protocolPayee).balance, 0.01 ether);
        assertEq(address(royaltyPayee).balance, 0.1 ether);
        assertEq(address(sellerPayee).balance, 0.89 ether);
        assertEq(ah.claimableFunds(address(sellerPayee), address(0)), 0);
        assertEq(nft.ownerOf(TOKEN), bidder1);
    }

    function test_observation_selfRecipients() public {
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.setProtocolFeeSettings(address(ah), 100);
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(0), 0, 0, 1 ether);
        cfg.payoutReceiver = address(ah);
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.list(cfg);
        cfg.payoutReceiver = payout;
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.updatePayoutReceiver(address(nft), TOKEN, address(ah));
        cfg.payoutReceiver = address(ah);
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.InvalidPayoutReceiver.selector);
        ah.updateListing(cfg);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.buyNow{value: 1 ether}(address(nft), TOKEN, address(ah), address(0), 1 ether, lid);
        vm.prank(bidder1);
        ah.buyNow{value: 1 ether}(address(nft), TOKEN, bidder1, address(0), 1 ether, lid);
        assertEq(nft.ownerOf(TOKEN), bidder1);
    }

    function test_observation_selfPrivateRecipient() public {
        ListingConfig memory cfg = _cfg(ListingType.PRIVATE_SALE, address(0), 0, 0, 1 ether);
        cfg.recipient = address(ah);
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.list(cfg);
        assertEq(nft.ownerOf(TOKEN), seller);
    }

    function testFuzz_observation_selfClaimRecipients(bool erc20) public {
        address currency = erc20 ? address(coin) : address(0);
        vm.prank(seller);
        ah.list(_cfg(ListingType.RESERVE_AUCTION, currency, 1 ether, 1 hours, 0));
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        if (erc20) {
            coin.transfer(bidder1, 1 ether);
            vm.prank(bidder1);
            coin.approve(address(ah), 1 ether);
        }
        vm.prank(bidder1);
        ah.bid{value: erc20 ? 0 : 1 ether}(address(nft), TOKEN, currency, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        vm.warp(l.startTime + l.duration + ah.SETTLEMENT_GRACE_PERIOD() + 1);
        vm.prank(bidder1);
        ah.cancelUnsettledAuction(address(nft), TOKEN);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.claimFunds(currency, address(ah));
        assertEq(ah.claimableFunds(bidder1, currency), 1 ether);
        vm.prank(seller);
        vm.expectRevert(TLAuctionHouse.InvalidRecipient.selector);
        ah.claimNft(address(nft), TOKEN, address(ah));
        vm.prank(bidder1);
        ah.claimFunds(currency, bidder1);
        vm.prank(seller);
        ah.claimNft(address(nft), TOKEN, seller);
        assertEq(nft.ownerOf(TOKEN), seller);
        assertEq(ah.claimableFunds(bidder1, currency), 0);
    }

    function test_observation_removedCurrencyCannotUpdate() public {
        ListingConfig memory cfg = _cfg(ListingType.BUY_NOW, address(coin), 0, 0, 1 ether);
        vm.prank(seller);
        ah.list(cfg);
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        ah.setCurrencyAllowed(address(coin), false);
        cfg.buyNowPrice = 2 ether;
        vm.prank(seller);
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        ah.updateListing(cfg);
        assertEq(ah.getListing(address(nft), TOKEN).id, lid);
        vm.prank(seller);
        ah.updatePayoutReceiver(address(nft), TOKEN, bidder2);
        assertEq(ah.getListing(address(nft), TOKEN).payoutReceiver, bidder2);
        ah.setCurrencyAllowed(address(coin), true);
        vm.prank(seller);
        ah.updateListing(cfg);
        assertEq(ah.getListing(address(nft), TOKEN).buyNowPrice, 2 ether);
    }

    /////////////////////////////////////////////////////////////////////
    // TIMING
    /////////////////////////////////////////////////////////////////////

    /// @dev HEX-020: an incumbent cannot invalidate a pending minimum bid with a last-second top up.
    function test_topUpBid_cannotSnipeChallenger() public {
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 hours);
        _bid(bidder1, 1 ether, lid);
        uint256 pendingBid = ah.getNextBid(address(nft), TOKEN);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        vm.warp(l.startTime + l.duration - 1);

        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.TopUpWindowClosed.selector);
        ah.topUpBid{value: 1}(address(nft), TOKEN, 1, lid);

        assertEq(ah.getNextBid(address(nft), TOKEN), pendingBid);
        _bid(bidder2, pendingBid, lid);
        l = ah.getListing(address(nft), TOKEN);
        assertEq(l.highestBidder, bidder2);
        assertEq(l.startTime + l.duration, block.timestamp + ah.EXTENSION_TIME());
    }

    /// @dev HEX-020: arbitrary positive top ups work before the cutoff, across currencies and auction modes.
    function testFuzz_topUpBid_windowBoundary(uint8 typeSeed, bool erc20, uint256 amount) public {
        amount = bound(amount, 1, 10 ether);
        ListingType type_ = typeSeed % 3 == 0
            ? ListingType.RESERVE_AUCTION
            : typeSeed % 3 == 1 ? ListingType.SCHEDULED_AUCTION : ListingType.RESERVE_AUCTION_PLUS_BUY_NOW;
        address currency = erc20 ? address(coin) : address(0);
        vm.prank(seller);
        ah.list(_cfg(type_, currency, 1 ether, 1 hours, 2 ether));
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        if (erc20) {
            coin.transfer(bidder1, 20 ether);
            vm.prank(bidder1);
            coin.approve(address(ah), type(uint256).max);
        }
        vm.prank(bidder1);
        ah.bid{value: erc20 ? 0 : 1 ether}(address(nft), TOKEN, currency, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        uint256 end = l.startTime + l.duration;

        // The last allowed second: no minimum increment and no change to the end.
        vm.warp(end - ah.EXTENSION_TIME() - 1);
        vm.prank(bidder1);
        ah.topUpBid{value: erc20 ? 0 : amount}(address(nft), TOKEN, amount, lid);
        l = ah.getListing(address(nft), TOKEN);
        assertEq(l.highestBid, 1 ether + amount);
        assertEq(l.startTime + l.duration, end);
        uint256 escrow = erc20 ? coin.balanceOf(address(ah)) : address(ah).balance;
        uint256 bidderBalance = erc20 ? coin.balanceOf(bidder1) : bidder1.balance;

        uint256[4] memory remaining = [ah.EXTENSION_TIME(), ah.EXTENSION_TIME() - 1, uint256(1), uint256(0)];
        for (uint256 i; i < remaining.length; ++i) {
            vm.warp(end - remaining[i]);
            vm.prank(bidder1);
            vm.expectRevert(TLAuctionHouse.TopUpWindowClosed.selector);
            ah.topUpBid{value: erc20 ? 0 : 1}(address(nft), TOKEN, 1, lid);
        }
        assertEq(ah.getListing(address(nft), TOKEN).highestBid, 1 ether + amount);
        assertEq(erc20 ? coin.balanceOf(address(ah)) : address(ah).balance, escrow);
        assertEq(erc20 ? coin.balanceOf(bidder1) : bidder1.balance, bidderBalance);

        vm.warp(end + 1);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.AuctionEnded.selector);
        ah.topUpBid{value: erc20 ? 0 : 1}(address(nft), TOKEN, 1, lid);
    }

    /// @dev Short auctions and extended auctions remain closed to top ups; regular self-bids still extend.
    function testFuzz_topUpBid_shortAuctionAndSelfBid(uint256 duration) public {
        duration = bound(duration, 0, ah.EXTENSION_TIME());
        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, duration);
        _bid(bidder1, 1 ether, lid);
        Listing memory l = ah.getListing(address(nft), TOKEN);
        uint256 end = l.startTime + l.duration;
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.TopUpWindowClosed.selector);
        ah.topUpBid{value: 1}(address(nft), TOKEN, 1, lid);

        vm.warp(end - 1);
        uint256 nextBid = ah.getNextBid(address(nft), TOKEN);
        uint256 previousBalance = bidder1.balance;
        _bid(bidder1, nextBid, lid);
        l = ah.getListing(address(nft), TOKEN);
        assertEq(l.startTime + l.duration, block.timestamp + ah.EXTENSION_TIME());
        assertEq(l.highestBid, nextBid);
        assertEq(previousBalance - bidder1.balance, nextBid - 1 ether);
        assertEq(address(ah).balance, nextBid);
        vm.prank(bidder1);
        vm.expectRevert(TLAuctionHouse.TopUpWindowClosed.selector);
        ah.topUpBid{value: 1}(address(nft), TOKEN, 1, lid);
    }

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
    function test_codelessEngineFallsBackToDirectRoyalties() public {
        RoyaltyLookup rl = new RoyaltyLookup(address(this));
        rl.setRoyaltyEngine(makeAddr("not a contract"));
        ah.setRoyaltyLookup(address(rl));

        uint256 lid = _listEth(ListingType.RESERVE_AUCTION, 0, 1 days);
        _bid(bidder1, 10 ether, lid);
        _settle();
        assertEq(creator.balance, 1 ether);
        assertEq(payout.balance, 9 ether - feeReceiver.balance);
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
    // HIGH-UNIT PERCENTAGE CALCULATIONS
    /////////////////////////////////////////////////////////////////////

    /// @dev HEX-018: a representable percentage must not overflow before division.
    function testFuzz_highUnitProtocolFee(uint256 value, bool fixedPrice) public {
        value = bound(value, type(uint256).max / 2, type(uint256).max);
        ah.setProtocolFeeSettings(feeReceiver, 500);
        ah.setRoyaltyLookup(address(0));
        vm.prank(creator);
        nft.setDefaultRoyalty(creator, 0);

        vm.prank(seller);
        ah.list(_cfg(fixedPrice ? ListingType.BUY_NOW : ListingType.RESERVE_AUCTION, address(coin), 1, 1 days, value));
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        coin.transfer(bidder1, value);
        vm.startPrank(bidder1);
        coin.approve(address(ah), value);
        if (fixedPrice) {
            ah.buyNow(address(nft), TOKEN, bidder1, address(coin), value, lid);
        } else {
            ah.bid(address(nft), TOKEN, address(coin), value, lid);
        }
        vm.stopPrank();
        if (!fixedPrice) _settle();

        assertEq(coin.balanceOf(feeReceiver), value / 20, "5% rounds down");
        assertEq(coin.balanceOf(payout), value - value / 20);
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(nft.ownerOf(TOKEN), bidder1);
    }

    /// @dev HEX-018: quote and settlement share a full-precision aggregate royalty cap.
    function testFuzz_highUnitRoyaltyCap(uint256 value) public {
        value = bound(value, type(uint256).max / 2, type(uint256).max);
        ah.setProtocolFeeSettings(feeReceiver, 500);
        _setRoyalty(royaltyLookup, royalty0, 5_000);

        (address payable[] memory recipients, uint256[] memory amounts) = ah.getRoyalty(address(nft), TOKEN, value);
        assertEq(recipients[0], royalty0);
        assertEq(amounts[0], value / 10, "10% cap rounds down");

        vm.prank(seller);
        ah.list(_cfg(ListingType.RESERVE_AUCTION, address(coin), 1, 1 days, 0));
        uint256 lid = ah.getListing(address(nft), TOKEN).id;
        coin.transfer(bidder1, value);
        vm.startPrank(bidder1);
        coin.approve(address(ah), value);
        ah.bid(address(nft), TOKEN, address(coin), value, lid);
        vm.stopPrank();
        _settle();

        assertEq(coin.balanceOf(royalty0), value / 10);
        assertEq(coin.balanceOf(feeReceiver), value / 20);
        assertEq(coin.balanceOf(payout), value - value / 10 - value / 20);
        assertEq(coin.balanceOf(address(ah)), 0);
        assertEq(nft.ownerOf(TOKEN), bidder1);
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

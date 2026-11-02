// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {stdError} from "forge-std-1.9.4/StdError.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {ERC1155TL} from "tl-creator-contracts-4.1.1/erc-1155/ERC1155TL.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {TLStacks1155} from "src/TLStacks1155.sol";
import {Drop} from "src/utils/TLStacks721Utils.sol";
import {Drop as Drop1155} from "src/utils/TLStacks1155Utils.sol";
import {DropPhase, DropType, DropErrors} from "src/utils/CommonUtils.sol";
import {MockSanctionsOracle} from "test/utils/MockSanctionsOracle.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

/// @dev Pins TLStacks721 behavior documented in docs/trust-model.md and docs/invariants.md, including properties
///      marked "On-chain: No" and admin-set values that break a drop until they are corrected
contract TLStacks721EdgeTest is Test, DropErrors {
    uint256 constant BASIS = 10_000;

    TLStacks721 stacks;
    ERC721TL nft;
    MockSanctionsOracle oracle;

    address admin = makeAddr("dropAdmin");
    address payout = makeAddr("payout");
    address feeReceiver = makeAddr("feeReceiver");
    address buyer = makeAddr("buyer");
    bytes32[] emptyProof;

    function test_pending_waiverRejectsSuccessorRound() public {
        stacks.waiveSellerFee(address(nft), 0);
        assertTrue(stacks.isSellerFeeWaived(address(nft)));
        _configure(DropType.REGULAR, 10, 0, 0);
        vm.prank(admin);
        stacks.closeDrop(address(nft));
        vm.expectRevert(DropRoundChanged.selector);
        stacks.waiveSellerFee(address(nft), 0);
        assertFalse(stacks.isSellerFeeWaived(address(nft)));
        stacks.waiveSellerFee(address(nft), 1); // deliberate waiver of the empty successor round
        _configure(DropType.REGULAR, 10, 0, 0);
        assertTrue(stacks.isSellerFeeWaived(address(nft)));
    }

    function test_pending_merkleVectorRegular() public {
        _checkMerkleVector(false);
    }

    function test_pending_merkleVectorSelected() public {
        _checkMerkleVector(true);
    }

    function _checkMerkleVector(bool selected) internal {
        Drop memory drop = _drop(selected ? DropType.SELECTABLE : DropType.REGULAR, 10, 0, 0);
        drop.presaleDuration = 1 hours;
        drop.presaleMerkleRoot = 0xa0a141551de2692f573b52765fbbc7e60173da2368b89948bae522a7c2cce0ff;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        address recipient = address(0x1111111111111111111111111111111111111111);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x2aef90b6985a8b20b48d621d20393a6b22ec2a2fbd4d3b841c860aedcb8aa754;
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        vm.prank(buyer);
        vm.expectRevert(NotOnAllowlist.selector);
        if (selected) {
            stacks.purchaseSelected{value: 0.001 ether}(address(nft), recipient, indices, 3, proof, address(0), 0, 0);
        } else {
            stacks.purchase{value: 0.001 ether}(address(nft), recipient, 1, 3, proof, address(0), 0, 0);
        }
        vm.prank(buyer);
        vm.expectRevert(NotOnAllowlist.selector);
        if (selected) {
            stacks.purchaseSelected{value: 0.001 ether}(address(nft), buyer, indices, 2, proof, address(0), 0, 0);
        } else {
            stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 2, proof, address(0), 0, 0);
        }
        vm.prank(buyer);
        if (selected) {
            stacks.purchaseSelected{value: 0.001 ether}(address(nft), recipient, indices, 2, proof, address(0), 0, 0);
        } else {
            stacks.purchase{value: 0.001 ether}(address(nft), recipient, 1, 2, proof, address(0), 0, 0);
        }
        assertEq(nft.balanceOf(recipient), 1);
    }

    function test_pending_negativeRateSaturatesBeforeMultiply() public {
        Drop memory drop = _drop(DropType.VELOCITY, 10, 0, 0);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = -type(int256).max;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        vm.prank(buyer);
        stacks.purchase{value: 0.003 ether}(address(nft), buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, 0);
        assertEq(stacks.getDrop(address(nft)).supply, 7);
    }

    function test_pending_rejectMinDecayRate() public {
        Drop memory drop = _drop(DropType.VELOCITY, 10, 0, 0);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = type(int256).min;
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidDecayRate()")));
        stacks.configureDrop(address(nft), drop);
        drop.decayRate = -1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidDecayRate()")));
        stacks.updateDropDecayRate(address(nft), type(int256).min);
        assertEq(stacks.getDrop(address(nft)).decayRate, -1);
    }

    function test_observation_constructorSelfFeeReceiver() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        new TLStacks721(address(this), address(0), predicted, 0, 0, 0);
        TLStacks721 zeroFee = new TLStacks721(address(this), address(0), address(0), 0, 0, 0);
        assertEq(zeroFee.protocolFeeReceiver(), address(0));
    }

    function test_observation_selfSelectedRecipient() public {
        _configure(DropType.SELECTABLE, 10, 0, 0);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 1;
        vm.prank(buyer);
        vm.expectRevert(InvalidRecipient.selector);
        stacks.purchaseSelected{value: 0.001 ether}(
            address(nft), address(stacks), indices, 0, emptyProof, address(0), 0, 0
        );
        assertFalse(stacks.isIndexMinted(address(nft), 1));
        vm.prank(buyer);
        stacks.purchaseSelected{value: 0.001 ether}(address(nft), buyer, indices, 0, emptyProof, address(0), 0, 0);
        assertTrue(stacks.isIndexMinted(address(nft), 1));
    }

    function test_observation_selfPayees() public {
        Drop memory drop = _drop(DropType.REGULAR, 10, 0, 0);
        drop.payoutReceiver = address(stacks);
        vm.prank(admin);
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.configureDrop(address(nft), drop);
        drop.payoutReceiver = payout;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        vm.prank(admin);
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.updateDropPayoutReceiver(address(nft), address(stacks));
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(address(stacks), 0, 0, 0);
        stacks.setProtocolFeeSettings(address(0), 0, 0, 0);
        assertEq(stacks.protocolFeeReceiver(), address(0));
    }

    function test_observation_selfMintRecipient() public {
        Drop memory drop = _drop(DropType.REGULAR, 10, 0, 0);
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("InvalidRecipient()")));
        stacks.purchase{value: 0.001 ether}(address(nft), address(stacks), 1, 0, emptyProof, address(0), 0, 0);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
    }

    function test_observation_renounceDisabled() public {
        address next = makeAddr("nextOwner");
        stacks.transferOwnership(next);
        stacks.pause(true);
        vm.expectRevert(bytes4(keccak256("OwnershipRenunciationDisabled()")));
        stacks.renounceOwnership();
        assertEq(stacks.owner(), address(this));
        assertEq(stacks.pendingOwner(), next);
        vm.prank(next);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", next));
        stacks.renounceOwnership();
        stacks.transferOwnership(address(0));
        assertEq(stacks.pendingOwner(), address(0));
        stacks.transferOwnership(next);
        vm.prank(next);
        stacks.acceptOwnership();
        assertEq(stacks.owner(), next);
        vm.prank(next);
        stacks.pause(false);
    }

    function test_deploymentCodeSize() public {
        assertLe(address(stacks).code.length, 24_576, "runtime exceeds EIP-170 deployment limit");
    }

    function setUp() public {
        vm.warp(1_000_000);
        oracle = new MockSanctionsOracle();
        stacks = new TLStacks721(address(this), address(oracle), feeReceiver, 0.001 ether, 500, 500);

        address[] memory empty = new address[](0);
        address[] memory minters = new address[](1);
        minters[0] = address(stacks);
        nft = new ERC721TL(false);
        nft.initialize("Edge", "EDGE", admin, 1_000, admin, empty, false, address(0), 0, address(0));
        vm.prank(admin);
        nft.setApprovedMintContracts(minters, true);
        vm.deal(buyer, 1_000 ether);
    }

    /// @dev I-15 and E-3 (not enforced on-chain): the flat ETH protocol fee has no cap, and because msg.value must
    ///      be exact, a fee change between signing and inclusion reverts the purchase rather than charging more
    function test_I15_E3_flatProtocolFeeUncappedButExact() public {
        _configure(DropType.REGULAR, 10, 1 ether, 0);
        uint256 signedValue = 1 ether + stacks.protocolFee();

        stacks.setProtocolFeeSettings(feeReceiver, 100 ether, 500, 500);
        assertEq(stacks.protocolFee(), 100 ether, "fee above the token price accepted");

        vm.prank(buyer);
        vm.expectRevert(IncorrectFunds.selector);
        stacks.purchase{value: signedValue}(address(nft), buyer, 1, 0, emptyProof, address(0), 1 ether, 0);

        // maxCostPerToken doesn't cover the flat fee, so a buyer who sends the new total pays it
        vm.prank(buyer);
        stacks.purchase{value: 101 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 1 ether, 0);
        assertEq(feeReceiver.balance, 100 ether + 1 ether * 500 / BASIS);
    }

    /// @dev HEX-022: both configuration routes validate the complete sum, not individual field widths.
    function testFuzz_scheduleLimit(uint64 start, uint64 presale, uint64 duration, bool updating) public {
        if (updating) _configure(DropType.REGULAR, 10, 0, 0);
        Drop memory previous = stacks.getDrop(address(nft));
        Drop memory drop = _drop(DropType.REGULAR, 10, 0, 0);
        drop.startTime = start;
        drop.presaleDuration = presale;
        drop.publicDuration = duration;
        bool valid = uint256(start) + uint256(presale) + uint256(duration) <= type(uint64).max;
        vm.prank(admin);
        if (!valid) vm.expectRevert(InvalidDropDuration.selector);
        if (updating) {
            stacks.updateDropDuration(address(nft), start, presale, duration);
        } else {
            stacks.configureDrop(address(nft), drop);
        }
        if (valid) {
            Drop memory actual = stacks.getDrop(address(nft));
            assertEq(actual.startTime, start);
            assertEq(actual.presaleDuration, presale);
            assertEq(actual.publicDuration, duration);
            stacks.getDropPhase(address(nft));
        } else {
            assertEq(abi.encode(stacks.getDrop(address(nft))), abi.encode(previous));
        }
        assertEq(stacks.getDropRound(address(nft)), 0);
    }

    function test_scheduleLimit_boundaries() public {
        Drop memory drop = _drop(DropType.REGULAR, 10, 0, 0);
        for (uint256 i; i < 3; ++i) {
            drop.startTime = i == 0 ? type(uint256).max : block.timestamp;
            drop.presaleDuration = i == 1 ? type(uint256).max : 0;
            drop.publicDuration = i == 2 ? type(uint256).max : 1 days;
            vm.prank(admin);
            vm.expectRevert(InvalidDropDuration.selector);
            stacks.configureDrop(address(nft), drop);
        }
        drop.startTime = block.timestamp;
        drop.presaleDuration = 1;
        drop.publicDuration = type(uint64).max - block.timestamp - 1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.PRESALE));
        vm.prank(admin);
        vm.expectRevert(InvalidDropDuration.selector);
        stacks.updateDropDuration(address(nft), drop.startTime, 1, drop.publicDuration + 1);
        vm.warp(drop.startTime + 1);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.PUBLIC_SALE));
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    /// @dev OBS-023: positive extensions cap at the uint64 schedule ceiling instead of reverting purchases
    function test_scheduleLimit_marathonExtension() public {
        Drop memory drop = _drop(DropType.REGULAR, 10, 0, 0);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = 1;
        drop.publicDuration = type(uint64).max - block.timestamp - 1;
        uint256 ceiling = drop.publicDuration + 1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, ceiling);

        // at the ceiling, further positive extensions are capped and purchases still succeed
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, ceiling);
        assertEq(stacks.getDrop(address(nft)).supply, 8);

        // zero and negative rates behave as before at the ceiling
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), 0);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, ceiling);
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), -1);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, ceiling - 1);

        // the largest positive rate is capped without overflowing
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), type(int256).max);
        vm.prank(buyer);
        stacks.purchase{value: 0.003 ether}(address(nft), buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, ceiling);
        assertEq(stacks.getDrop(address(nft)).supply, 3);
        assertEq(nft.balanceOf(buyer), 7);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.PUBLIC_SALE));
    }

    /// @dev HEX-022: an invalid duration update leaves the drop usable.
    function test_scheduleLimit_rejectsOverflowingUpdate() public {
        _configure(DropType.REGULAR, 10, 0, 0);
        vm.prank(admin);
        vm.expectRevert(InvalidDropDuration.selector);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, type(uint256).max);
        assertEq(stacks.getDrop(address(nft)).publicDuration, 1 days);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.PUBLIC_SALE));
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    /// @dev Reject an unusable rate without disrupting an existing drop.
    function test_decayRateIntMin_rejectsUpdateAndPreservesPurchases() public {
        _configure(DropType.VELOCITY, 10, 0, -1);
        vm.prank(admin);
        vm.expectRevert(InvalidDecayRate.selector);
        stacks.updateDropDecayRate(address(nft), type(int256).min);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    /// @dev HEX-022/OBS-023: a huge positive rate caps the schedule at the uint64 ceiling on the first mint
    function test_scheduleLimit_hugeMarathonRateCapsAtCeiling() public {
        _configure(DropType.VELOCITY, 10, 0, type(int256).max);
        uint256 startTime = stacks.getDrop(address(nft)).startTime;
        vm.prank(buyer);
        stacks.purchase{value: 0.003 ether}(address(nft), buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).supply, 7);
        assertEq(stacks.getDrop(address(nft)).publicDuration, type(uint64).max - startTime);
        assertEq(nft.balanceOf(buyer), 3);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, type(uint64).max - startTime);
        assertEq(nft.balanceOf(buyer), 4);
    }

    function test_G58_closeDropWhilePausedAndSanctioned() public {
        _configure(DropType.REGULAR, 10, 0, 0);
        stacks.pause(true);
        oracle.setSanctioned(admin, true);

        vm.prank(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stacks.updateDropAllowance(address(nft), 5);

        vm.prank(admin);
        stacks.closeDrop(address(nft));
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.NOT_CONFIGURED));
        assertEq(stacks.getDropRound(address(nft)), 1);
    }

    /// @dev I-7: reconfiguring after a sell-out or after the window closes starts a new round with no waiver and
    ///      fresh per-wallet counts, and the seller fee applies again
    function test_I7_reconfigureStartsFreshRound() public {
        stacks.waiveSellerFee(address(nft), 0);
        _configure(DropType.REGULAR, 2, 1 ether, 0);
        vm.prank(buyer);
        stacks.purchase{value: 2 * (1 ether + 0.001 ether)}(
            address(nft), buyer, 2, 0, emptyProof, address(0), 1 ether, 0
        );
        assertEq(payout.balance, 2 ether, "waived round charged a seller fee");
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.ENDED), "sold out");

        // sold out -> reconfigure bumps the round
        _configure(DropType.REGULAR, 2, 1 ether, 0);
        assertEq(stacks.getDropRound(address(nft)), 1);
        assertFalse(stacks.isSellerFeeWaived(address(nft)), "waiver carried into a new round");
        (, uint256 publicMinted) = stacks.getNumberMinted(address(nft), buyer);
        assertEq(publicMinted, 0, "per-wallet count carried into a new round");

        vm.prank(buyer);
        stacks.purchase{value: 1 ether + 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 1 ether, 1);
        assertEq(payout.balance, 2 ether + 1 ether * (BASIS - 500) / BASIS, "seller fee not charged in new round");

        // time ended -> reconfigure bumps the round again
        vm.warp(block.timestamp + 1 days);
        _configure(DropType.REGULAR, 2, 1 ether, 0);
        assertEq(stacks.getDropRound(address(nft)), 2);
    }

    /// @dev HEX-034: regular and selectable purchases support representable fees at high raw token values.
    function testFuzz_highUnitSellerFee(uint256 cost, bool selectable) public {
        cost = bound(cost, type(uint256).max / 2, type(uint256).max);
        MockERC20 coin = new MockERC20(buyer);
        stacks.setCurrencyAllowed(address(coin), true);
        Drop memory drop = _drop(selectable ? DropType.SELECTABLE : DropType.REGULAR, 1, cost, 0);
        drop.currencyAddress = address(coin);
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);

        vm.startPrank(buyer);
        coin.approve(address(stacks), cost);
        if (selectable) {
            uint256[] memory indices = new uint256[](1);
            stacks.purchaseSelected(address(nft), buyer, indices, 0, emptyProof, address(coin), cost, 0);
        } else {
            stacks.purchase(address(nft), buyer, 1, 0, emptyProof, address(coin), cost, 0);
        }
        vm.stopPrank();

        assertEq(coin.balanceOf(feeReceiver), cost / 20, "5% rounds down");
        assertEq(coin.balanceOf(payout), cost - cost / 20);
        assertEq(coin.balanceOf(buyer), type(uint256).max - cost);
        assertEq(coin.balanceOf(address(stacks)), 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    function _drop(DropType dropType, uint256 supply, uint256 cost, int256 decayRate)
        internal
        view
        returns (Drop memory)
    {
        return Drop(
            dropType,
            payout,
            supply,
            supply,
            supply,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1 days,
            cost,
            decayRate,
            "ipfs://drop"
        );
    }

    function _configure(DropType dropType, uint256 supply, uint256 cost, int256 decayRate) internal {
        vm.prank(admin);
        stacks.configureDrop(address(nft), _drop(dropType, supply, cost, decayRate));
    }
}

/// @dev TLStacks1155 counterparts of the pins above that differ by token id
contract TLStacks1155EdgeTest is Test, DropErrors {
    uint256 constant TOKEN = 1;

    TLStacks1155 stacks;
    ERC1155TL nft;
    address admin = makeAddr("dropAdmin");
    address payout = makeAddr("payout");
    address buyer = makeAddr("buyer");
    bytes32[] emptyProof;

    function test_pending_waiverRejectsSuccessorRound() public {
        stacks.waiveSellerFee(address(nft), TOKEN, 0);
        assertTrue(stacks.isSellerFeeWaived(address(nft), TOKEN));
        _configure(TOKEN, 10);
        vm.prank(admin);
        stacks.closeDrop(address(nft), TOKEN);
        vm.expectRevert(DropRoundChanged.selector);
        stacks.waiveSellerFee(address(nft), TOKEN, 0);
        assertFalse(stacks.isSellerFeeWaived(address(nft), TOKEN));
        stacks.waiveSellerFee(address(nft), TOKEN, 1); // deliberate waiver of the empty successor round
        _configure(TOKEN, 10);
        assertTrue(stacks.isSellerFeeWaived(address(nft), TOKEN));
    }

    function test_pending_merkleVector() public {
        Drop1155 memory drop = _drop(10);
        drop.presaleDuration = 1 hours;
        drop.presaleMerkleRoot = 0xa0a141551de2692f573b52765fbbc7e60173da2368b89948bae522a7c2cce0ff;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        address recipient = address(0x1111111111111111111111111111111111111111);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x2aef90b6985a8b20b48d621d20393a6b22ec2a2fbd4d3b841c860aedcb8aa754;
        vm.prank(buyer);
        vm.expectRevert(NotOnAllowlist.selector);
        stacks.purchase(address(nft), TOKEN, recipient, 1, 3, proof, address(0), 0, 0);
        vm.prank(buyer);
        vm.expectRevert(NotOnAllowlist.selector);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 2, proof, address(0), 0, 0);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, recipient, 1, 2, proof, address(0), 0, 0);
        assertEq(nft.balanceOf(recipient, TOKEN), 1);
    }

    function test_pending_negativeRateSaturatesBeforeMultiply() public {
        Drop1155 memory drop = _drop(10);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = -type(int256).max;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        vm.prank(buyer);
        stacks.purchase{value: 0}(address(nft), TOKEN, buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).supply, 7);
    }

    function test_pending_rejectMinDecayRate() public {
        Drop1155 memory drop = _drop(10);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = type(int256).min;
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidDecayRate()")));
        stacks.configureDrop(address(nft), TOKEN, drop);
        drop.decayRate = -1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidDecayRate()")));
        stacks.updateDropDecayRate(address(nft), TOKEN, type(int256).min);
        assertEq(stacks.getDrop(address(nft), TOKEN).decayRate, -1);
    }

    function test_observation_constructorSelfFeeReceiver() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        new TLStacks1155(address(this), address(0), predicted, 0, 0, 0);
        TLStacks1155 zeroFee = new TLStacks1155(address(this), address(0), address(0), 0, 0, 0);
        assertEq(zeroFee.protocolFeeReceiver(), address(0));
    }

    function test_observation_selfPayees() public {
        Drop1155 memory drop = _drop(10);
        drop.payoutReceiver = address(stacks);
        vm.prank(admin);
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.configureDrop(address(nft), TOKEN, drop);
        drop.payoutReceiver = payout;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        vm.prank(admin);
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.updateDropPayoutReceiver(address(nft), TOKEN, address(stacks));
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(address(stacks), 0, 0, 0);
        stacks.setProtocolFeeSettings(address(0), 0, 0, 0);
        assertEq(stacks.protocolFeeReceiver(), address(0));
    }

    function test_observation_selfMintRecipient() public {
        Drop1155 memory drop = _drop(10);
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("InvalidRecipient()")));
        stacks.purchase(address(nft), TOKEN, address(stacks), 1, 0, emptyProof, address(0), 0, 0);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
    }

    function test_observation_renounceDisabled() public {
        address next = makeAddr("nextOwner");
        stacks.transferOwnership(next);
        stacks.pause(true);
        vm.expectRevert(bytes4(keccak256("OwnershipRenunciationDisabled()")));
        stacks.renounceOwnership();
        assertEq(stacks.owner(), address(this));
        assertEq(stacks.pendingOwner(), next);
        vm.prank(next);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", next));
        stacks.renounceOwnership();
        stacks.transferOwnership(address(0));
        assertEq(stacks.pendingOwner(), address(0));
        stacks.transferOwnership(next);
        vm.prank(next);
        stacks.acceptOwnership();
        assertEq(stacks.owner(), next);
        vm.prank(next);
        stacks.pause(false);
    }

    function test_deploymentCodeSize() public {
        assertLe(address(stacks).code.length, 24_576, "runtime exceeds EIP-170 deployment limit");
    }

    function setUp() public {
        vm.warp(1_000_000);
        stacks = new TLStacks1155(address(this), address(0), makeAddr("feeReceiver"), 0, 0, 0);

        address[] memory empty = new address[](0);
        address[] memory minters = new address[](1);
        minters[0] = address(stacks);
        nft = new ERC1155TL(false);
        nft.initialize("Edge", "EDGE", admin, 1_000, admin, empty, false, address(0), 0);
        address[] memory holders = new address[](1);
        holders[0] = admin;
        uint256[] memory amounts = new uint256[](1);
        vm.startPrank(admin);
        nft.setApprovedMintContracts(minters, true);
        nft.createToken("https://arweave.net/1", holders, amounts);
        nft.createToken("https://arweave.net/2", holders, amounts);
        vm.stopPrank();
    }

    /// @dev HEX-021: missing token IDs cannot acquire drop terms, including zero and far-future IDs.
    function testFuzz_configureDrop_rejectsUncreatedToken(uint256 tokenId, bool zeroId) public {
        tokenId = zeroId ? 0 : bound(tokenId, 3, type(uint256).max);
        vm.expectRevert(TokenDoesntExist.selector);
        _configure(tokenId, 1);
        assertEq(uint8(stacks.getDrop(address(nft), tokenId).dropType), uint8(DropType.NOT_CONFIGURED));
        assertEq(stacks.getDrop(address(nft), tokenId).payoutReceiver, address(0));
        assertEq(stacks.getDropRound(address(nft), tokenId), 0);
    }

    /// @dev HEX-021: creation by a successor cannot activate a predecessor's attempted future-token drop.
    function test_configureDrop_futureTokenAfterOwnershipTransfer() public {
        uint256 futureToken = 3;
        vm.expectRevert(TokenDoesntExist.selector);
        _configure(futureToken, 1);

        address successor = makeAddr("successor");
        vm.prank(admin);
        nft.transferOwnership(successor);
        assertEq(nft.owner(), successor);

        address[] memory holders = new address[](1);
        holders[0] = successor;
        uint256[] memory amounts = new uint256[](1);
        vm.prank(successor);
        nft.createToken("https://arweave.net/3", holders, amounts);
        assertTrue(nft.getTokenDetails(futureToken).created);
        assertEq(nft.balanceOf(successor, futureToken), 0, "creation need not mint supply");
        assertEq(uint8(stacks.getDropPhase(address(nft), futureToken)), uint8(DropPhase.NOT_CONFIGURED));

        vm.prank(buyer);
        vm.expectRevert(YouShallNotMint.selector);
        stacks.purchase(address(nft), futureToken, buyer, 1, 0, emptyProof, address(0), 0, 0);

        // The revoked owner cannot configure it now; the successor explicitly chooses the sale terms.
        vm.expectRevert(NotDropAdmin.selector);
        _configure(futureToken, 1);
        admin = successor;
        payout = successor;
        _configure(futureToken, 1);
        vm.prank(successor);
        stacks.updateDropPrices(address(nft), futureToken, address(0), 0, 1 ether);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        stacks.purchase{value: 1 ether}(address(nft), futureToken, buyer, 1, 0, emptyProof, address(0), 1 ether, 0);
        assertEq(nft.balanceOf(buyer, futureToken), 1);
        assertEq(successor.balance, 1 ether);
        assertEq(stacks.getDropRound(address(nft), futureToken), 0);
    }

    /// @dev Selling out ends the drop for that token id only, and reconfiguring it starts a new round
    function test_sellOut_endsDropAndReconfigureBumpsRound() public {
        _configure(TOKEN, 3);
        _configure(TOKEN + 1, 3);

        vm.startPrank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer, TOKEN), 3);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.ENDED));
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN + 1)), uint8(DropPhase.PUBLIC_SALE), "other id ended");

        vm.expectRevert(YouShallNotMint.selector);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        vm.stopPrank();

        _configure(TOKEN, 3);
        assertEq(stacks.getDropRound(address(nft), TOKEN), 1);
        assertEq(stacks.getDropRound(address(nft), TOKEN + 1), 0, "other id's round moved");
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 3, 0, emptyProof, address(0), 0, 1);
        assertEq(nft.balanceOf(buyer, TOKEN), 6);
    }

    /// @dev HEX-022: both configuration routes validate the complete sum, not individual field widths.
    function testFuzz_scheduleLimit(uint64 start, uint64 presale, uint64 duration, bool updating) public {
        if (updating) _configure(TOKEN, 10);
        Drop1155 memory previous = stacks.getDrop(address(nft), TOKEN);
        Drop1155 memory drop = _drop(10);
        drop.startTime = start;
        drop.presaleDuration = presale;
        drop.publicDuration = duration;
        bool valid = uint256(start) + uint256(presale) + uint256(duration) <= type(uint64).max;
        vm.prank(admin);
        if (!valid) vm.expectRevert(InvalidDropDuration.selector);
        if (updating) {
            stacks.updateDropDuration(address(nft), TOKEN, start, presale, duration);
        } else {
            stacks.configureDrop(address(nft), TOKEN, drop);
        }
        if (valid) {
            Drop1155 memory actual = stacks.getDrop(address(nft), TOKEN);
            assertEq(actual.startTime, start);
            assertEq(actual.presaleDuration, presale);
            assertEq(actual.publicDuration, duration);
            stacks.getDropPhase(address(nft), TOKEN);
        } else {
            assertEq(abi.encode(stacks.getDrop(address(nft), TOKEN)), abi.encode(previous));
        }
        assertEq(stacks.getDropRound(address(nft), TOKEN), 0);
    }

    function test_scheduleLimit_boundaries() public {
        Drop1155 memory drop = _drop(10);
        for (uint256 i; i < 3; ++i) {
            drop.startTime = i == 0 ? type(uint256).max : block.timestamp;
            drop.presaleDuration = i == 1 ? type(uint256).max : 0;
            drop.publicDuration = i == 2 ? type(uint256).max : 1 days;
            vm.prank(admin);
            vm.expectRevert(InvalidDropDuration.selector);
            stacks.configureDrop(address(nft), TOKEN, drop);
        }
        drop.startTime = block.timestamp;
        drop.presaleDuration = 1;
        drop.publicDuration = type(uint64).max - block.timestamp - 1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.PRESALE));
        vm.prank(admin);
        vm.expectRevert(InvalidDropDuration.selector);
        stacks.updateDropDuration(address(nft), TOKEN, drop.startTime, 1, drop.publicDuration + 1);
        vm.warp(drop.startTime + 1);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.PUBLIC_SALE));
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer, TOKEN), 1);
    }

    /// @dev OBS-023: positive extensions cap at the uint64 schedule ceiling instead of reverting purchases
    function test_scheduleLimit_marathonExtension() public {
        Drop1155 memory drop = _drop(10);
        drop.dropType = DropType.VELOCITY;
        drop.decayRate = 1;
        drop.publicDuration = type(uint64).max - block.timestamp - 1;
        uint256 ceiling = drop.publicDuration + 1;
        vm.prank(admin);
        stacks.configureDrop(address(nft), TOKEN, drop);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, ceiling);

        // at the ceiling, further positive extensions are capped and purchases still succeed
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, ceiling);
        assertEq(stacks.getDrop(address(nft), TOKEN).supply, 8);

        // zero and negative rates behave as before at the ceiling
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), TOKEN, 0);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, ceiling);
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), TOKEN, -1);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, ceiling - 1);

        // the largest positive rate is capped without overflowing
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), TOKEN, type(int256).max);
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 3, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, ceiling);
        assertEq(stacks.getDrop(address(nft), TOKEN).supply, 3);
        assertEq(nft.balanceOf(buyer, TOKEN), 7);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.PUBLIC_SALE));
    }

    /// @dev HEX-022: an invalid duration update leaves the drop usable.
    function test_scheduleLimit_rejectsOverflowingUpdate() public {
        _configure(TOKEN, 3);
        vm.prank(admin);
        vm.expectRevert(InvalidDropDuration.selector);
        stacks.updateDropDuration(address(nft), TOKEN, block.timestamp, 0, type(uint256).max);
        assertEq(stacks.getDrop(address(nft), TOKEN).publicDuration, 1 days);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.PUBLIC_SALE));
        vm.prank(buyer);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer, TOKEN), 1);
    }

    /// @dev HEX-034: a representable seller fee must not overflow its intermediate multiplication.
    function testFuzz_highUnitSellerFee(uint256 cost) public {
        cost = bound(cost, type(uint256).max / 2, type(uint256).max);
        MockERC20 coin = new MockERC20(buyer);
        address feeReceiver = stacks.protocolFeeReceiver();
        stacks.setProtocolFeeSettings(feeReceiver, 0, 0, 500);
        stacks.setCurrencyAllowed(address(coin), true);
        _configure(TOKEN, 1);
        vm.prank(admin);
        stacks.updateDropPrices(address(nft), TOKEN, address(coin), 0, cost);

        vm.startPrank(buyer);
        coin.approve(address(stacks), cost);
        stacks.purchase(address(nft), TOKEN, buyer, 1, 0, emptyProof, address(coin), cost, 0);
        vm.stopPrank();

        assertEq(coin.balanceOf(feeReceiver), cost / 20, "5% rounds down");
        assertEq(coin.balanceOf(payout), cost - cost / 20);
        assertEq(coin.balanceOf(buyer), type(uint256).max - cost);
        assertEq(coin.balanceOf(address(stacks)), 0);
        assertEq(nft.balanceOf(buyer, TOKEN), 1);
    }

    function _drop(uint256 supply) internal view returns (Drop1155 memory) {
        return Drop1155(
            DropType.REGULAR,
            payout,
            supply,
            supply,
            supply,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1 days,
            0,
            0
        );
    }

    function _configure(uint256 tokenId, uint256 supply) internal {
        vm.prank(admin);
        stacks.configureDrop(address(nft), tokenId, _drop(supply));
    }
}

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

    /// @dev A public duration that overflows `startTime + presaleDuration + publicDuration` makes the phase view
    ///      revert, which blocks purchases, every update, and reconfiguring; `closeDrop` doesn't read the phase and
    ///      is the way out
    function test_durationOverflow_bricksDropUntilClosed() public {
        _configure(DropType.REGULAR, 10, 0, 0);
        vm.prank(admin);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        stacks.getDropPhase(address(nft));
        vm.prank(buyer);
        vm.expectRevert(stdError.arithmeticError);
        stacks.purchase(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        vm.prank(admin);
        vm.expectRevert(stdError.arithmeticError);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, 1 days);
        vm.prank(admin);
        vm.expectRevert(stdError.arithmeticError);
        stacks.configureDrop(address(nft), _drop(DropType.REGULAR, 10, 0, 0));

        vm.prank(admin);
        stacks.closeDrop(address(nft));
        _configure(DropType.REGULAR, 10, 0, 0);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.PUBLIC_SALE));
        assertEq(stacks.getDropRound(address(nft)), 1);
    }

    /// @dev A velocity decay rate of int256 min can't be negated, so every purchase reverts until the admin changes
    ///      the rate
    function test_decayRateIntMin_revertsPurchasesUntilUpdated() public {
        _configure(DropType.VELOCITY, 10, 0, -1);
        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), type(int256).min);

        vm.prank(buyer);
        vm.expectRevert(stdError.arithmeticError);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);

        vm.prank(admin);
        stacks.updateDropDecayRate(address(nft), -1);
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    /// @dev A huge positive decay rate lets one purchase through, then overflows the public duration on the next
    ///      until the admin resets the rate and duration
    function test_hugePositiveDecayRate_overflowsOnSecondPurchase() public {
        _configure(DropType.VELOCITY, 10, 0, type(int256).max);

        vm.startPrank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        vm.expectRevert(stdError.arithmeticError);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        vm.stopPrank();

        vm.startPrank(admin);
        stacks.updateDropDecayRate(address(nft), 0);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, 1 days);
        vm.stopPrank();
        vm.prank(buyer);
        stacks.purchase{value: 0.001 ether}(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(nft.balanceOf(buyer), 2);
    }

    /// @dev G-58: closeDrop is gated only by drop admin, so it works while paused and for a sanctioned admin
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
        stacks.waiveSellerFee(address(nft));
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

    /// @dev Same overflow as the 721 test: the phase view reverts until the drop is closed
    function test_durationOverflow_bricksDropUntilClosed() public {
        _configure(TOKEN, 3);
        vm.prank(admin);
        stacks.updateDropDuration(address(nft), TOKEN, block.timestamp, 0, type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        stacks.getDropPhase(address(nft), TOKEN);

        vm.prank(admin);
        stacks.closeDrop(address(nft), TOKEN);
        _configure(TOKEN, 3);
        assertEq(uint8(stacks.getDropPhase(address(nft), TOKEN)), uint8(DropPhase.PUBLIC_SALE));
    }

    function _configure(uint256 tokenId, uint256 supply) internal {
        Drop1155 memory drop = Drop1155(
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
        vm.prank(admin);
        stacks.configureDrop(address(nft), tokenId, drop);
    }
}

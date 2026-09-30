// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {StdInvariant} from "forge-std-1.9.4/StdInvariant.sol";
import {TLStacks1155} from "src/TLStacks1155.sol";
import {Drop} from "src/utils/TLStacks1155Utils.sol";
import {DropType} from "src/utils/CommonUtils.sol";
import {Stacks1155Handler} from "test/invariant/handlers/Stacks1155Handler.sol";

/// @dev Stateful invariants for TLStacks1155. IDs refer to docs/invariants.md and docs/trust-model.md.
contract TLStacks1155InvariantTest is Test {
    Stacks1155Handler handler;
    TLStacks1155 stacks;
    address nft;

    function setUp() public {
        handler = new Stacks1155Handler();
        stacks = handler.stacks();
        nft = address(handler.nft());

        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = Stacks1155Handler.configureDrop.selector;
        selectors[1] = Stacks1155Handler.updateDropPayoutReceiver.selector;
        selectors[2] = Stacks1155Handler.updateDropAllowance.selector;
        selectors[3] = Stacks1155Handler.updateDropPrices.selector;
        selectors[4] = Stacks1155Handler.updateDropDuration.selector;
        selectors[5] = Stacks1155Handler.updateDropPresaleMerkleRoot.selector;
        selectors[6] = Stacks1155Handler.updateDropDecayRate.selector;
        selectors[7] = Stacks1155Handler.updateDropSupply.selector;
        selectors[8] = Stacks1155Handler.closeDrop.selector;
        selectors[9] = Stacks1155Handler.purchase.selector;
        selectors[10] = Stacks1155Handler.warp.selector;
        selectors[11] = Stacks1155Handler.setProtocolFeeSettings.selector;
        selectors[12] = Stacks1155Handler.waiveSellerFee.selector;
        selectors[13] = Stacks1155Handler.setPaused.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev I-2 and I-12: remaining supply plus everything minted this round equals the drop total, per token id
    function invariant_supplyConservation() public view {
        for (uint256 tokenId = 1; tokenId <= handler.NUM_TOKENS(); ++tokenId) {
            Drop memory drop = stacks.getDrop(nft, tokenId);
            if (drop.dropType == DropType.NOT_CONFIGURED) continue;
            assertTrue(drop.dropType != DropType.SELECTABLE, "selectable drop stored on 1155");
            assertLe(drop.supply, drop.initialSupply, "I-12: supply above initial supply");
            uint256 minted;
            for (uint256 a = 0; a < handler.numActors(); ++a) {
                (uint256 presale, uint256 public_) = stacks.getNumberMinted(nft, tokenId, handler.actors(a));
                minted += presale + public_;
            }
            assertEq(drop.initialSupply, drop.supply + minted, "I-2: supply + minted != initial supply");
        }
    }

    /// @dev I-4
    function invariant_sellerFeeBounds() public view {
        assertLe(stacks.ethSellerFeeBps(), stacks.MAX_SELLER_FEE_BPS(), "I-4: eth seller fee above cap");
        assertLe(stacks.erc20SellerFeeBps(), stacks.MAX_SELLER_FEE_BPS(), "I-4: erc20 seller fee above cap");
    }

    /// @dev I-7 and rounds: the round only moves by close/reconfigure, and a round's waiver is never cleared
    function invariant_roundsAndWaivers() public view {
        for (uint256 tokenId = 1; tokenId <= handler.NUM_TOKENS(); ++tokenId) {
            uint256 round = stacks.getDropRound(nft, tokenId);
            assertEq(round, handler.ghostRound(tokenId), "round moved unexpectedly");
            assertEq(
                stacks.isSellerFeeWaived(nft, tokenId),
                handler.ghostWaived(tokenId, round),
                "I-7: waiver changed in a round"
            );
        }
    }

    /// @dev Trust model §8: purchases leave no balance behind, and every unit paid in reached a payee
    function invariant_noCustodyAndValueConservation() public view {
        assertEq(address(stacks).balance, 0, "stacks holds ETH");
        assertEq(handler.coin().balanceOf(address(stacks)), 0, "stacks holds ERC-20");

        address feeReceiver = handler.feeReceiver();
        uint256 eth = feeReceiver.balance;
        uint256 erc20 = handler.coin().balanceOf(feeReceiver);
        for (uint256 i = 0; i < handler.numPayoutReceivers(); ++i) {
            address receiver = handler.payoutReceivers(i);
            eth += receiver.balance;
            erc20 += handler.coin().balanceOf(receiver);
        }
        assertEq(eth, handler.ghostEthPaid(), "ETH paid in != ETH received by payees");
        assertEq(erc20, handler.ghostCoinPaid(), "ERC-20 paid in != ERC-20 received by payees");
    }

    /// @dev Every token held by a recipient was minted by a tracked purchase
    function invariant_mintedTokensAccounted() public view {
        for (uint256 tokenId = 1; tokenId <= handler.NUM_TOKENS(); ++tokenId) {
            uint256 held;
            for (uint256 a = 0; a < handler.numActors(); ++a) {
                held += handler.nft().balanceOf(handler.actors(a), tokenId);
            }
            assertEq(held, handler.ghostMinted(tokenId), "recipient balances != tracked mints");
        }
    }

    /// @dev Per-call properties checked inside the handler (E-2, G-*)
    function invariant_handlerAssertions() public view {
        assertEq(handler.violations(), 0, handler.lastViolation());
    }

    /// @dev Require successful ETH and ERC-20 purchases on separate token ids.
    function test_successfulEthAndErc20Purchases() public {
        vm.startPrank(handler.admin());
        stacks.configureDrop(
            nft,
            1,
            Drop(
                DropType.REGULAR,
                handler.payoutReceivers(0),
                10,
                10,
                10,
                address(0),
                block.timestamp,
                0,
                0,
                bytes32(0),
                1 days,
                1 ether,
                0
            )
        );
        stacks.configureDrop(
            nft,
            2,
            Drop(
                DropType.REGULAR,
                handler.payoutReceivers(1),
                10,
                10,
                10,
                address(handler.coin()),
                block.timestamp,
                0,
                0,
                bytes32(0),
                1 days,
                1 ether,
                0
            )
        );
        vm.stopPrank();

        handler.purchase(0, 0, 0, 1, 2);
        handler.purchase(1, 1, 1, 1, 2);
        assertEq(handler.successes("purchase"), 2, "one of the purchases did not succeed");

        invariant_supplyConservation();
        invariant_noCustodyAndValueConservation();
        invariant_mintedTokensAccounted();
        invariant_handlerAssertions();
    }
}

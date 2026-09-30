// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {StdInvariant} from "forge-std-1.9.4/StdInvariant.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {Drop} from "src/utils/TLStacks721Utils.sol";
import {DropType} from "src/utils/CommonUtils.sol";
import {Stacks721Handler} from "test/invariant/handlers/Stacks721Handler.sol";

/// @dev Stateful invariants for TLStacks721. IDs refer to docs/invariants.md and docs/trust-model.md.
contract TLStacks721InvariantTest is Test {
    Stacks721Handler handler;
    TLStacks721 stacks;

    function setUp() public {
        handler = new Stacks721Handler();
        stacks = handler.stacks();

        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = Stacks721Handler.configureDrop.selector;
        selectors[1] = Stacks721Handler.updateDropPayoutReceiver.selector;
        selectors[2] = Stacks721Handler.updateDropAllowance.selector;
        selectors[3] = Stacks721Handler.updateDropPrices.selector;
        selectors[4] = Stacks721Handler.updateDropDuration.selector;
        selectors[5] = Stacks721Handler.updateDropPresaleMerkleRoot.selector;
        selectors[6] = Stacks721Handler.updateDropDecayRate.selector;
        selectors[7] = Stacks721Handler.updateDropSupply.selector;
        selectors[8] = Stacks721Handler.closeDrop.selector;
        selectors[9] = Stacks721Handler.purchase.selector;
        selectors[10] = Stacks721Handler.purchaseSelected.selector;
        selectors[11] = Stacks721Handler.warp.selector;
        selectors[12] = Stacks721Handler.setProtocolFeeSettings.selector;
        selectors[13] = Stacks721Handler.waiveSellerFee.selector;
        selectors[14] = Stacks721Handler.setPaused.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev I-1 and I-12: remaining supply plus everything minted this round equals the drop total
    function invariant_supplyConservation() public view {
        for (uint256 i = 0; i < 2; ++i) {
            address nft = handler.nfts(i);
            Drop memory drop = stacks.getDrop(nft);
            if (drop.dropType == DropType.NOT_CONFIGURED) continue;
            assertLe(drop.supply, drop.initialSupply, "I-12: supply above initial supply");
            uint256 minted;
            for (uint256 a = 0; a < handler.numActors(); ++a) {
                (uint256 presale, uint256 public_) = stacks.getNumberMinted(nft, handler.actors(a));
                minted += presale + public_;
            }
            assertEq(drop.initialSupply, drop.supply + minted, "I-1: supply + minted != initial supply");
        }
    }

    /// @dev Selectable drops: the minted-index bitmap has exactly one bit per token minted this round
    function invariant_selectableBitmap() public view {
        for (uint256 i = 0; i < 2; ++i) {
            address nft = handler.nfts(i);
            Drop memory drop = stacks.getDrop(nft);
            if (drop.dropType != DropType.SELECTABLE) continue;
            uint256[] memory words = stacks.getMintedIndices(nft);
            uint256 bits;
            for (uint256 w = 0; w < words.length; ++w) {
                bits += _popcount(words[w]);
            }
            assertEq(bits, drop.initialSupply - drop.supply, "bitmap popcount != minted this round");
        }
    }

    /// @dev I-4
    function invariant_sellerFeeBounds() public view {
        assertLe(stacks.ethSellerFeeBps(), stacks.MAX_SELLER_FEE_BPS(), "I-4: eth seller fee above cap");
        assertLe(stacks.erc20SellerFeeBps(), stacks.MAX_SELLER_FEE_BPS(), "I-4: erc20 seller fee above cap");
    }

    /// @dev I-7 and rounds: the round only moves by close/reconfigure, and a round's waiver is never cleared
    function invariant_roundsAndWaivers() public view {
        for (uint256 i = 0; i < 2; ++i) {
            address nft = handler.nfts(i);
            uint256 round = stacks.getDropRound(nft);
            assertEq(round, handler.ghostRound(nft), "round moved unexpectedly");
            assertEq(stacks.isSellerFeeWaived(nft), handler.ghostWaived(nft, round), "I-7: waiver changed in a round");
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

    /// @dev Every token that exists was minted by a tracked purchase and delivered to a tracked recipient
    function invariant_mintedTokensAccounted() public view {
        for (uint256 i = 0; i < 2; ++i) {
            ERC721TL nft = ERC721TL(handler.nfts(i));
            uint256 held;
            for (uint256 a = 0; a < handler.numActors(); ++a) {
                held += nft.balanceOf(handler.actors(a));
            }
            assertEq(nft.totalSupply(), handler.ghostMinted(address(nft)), "total supply != tracked mints");
            assertEq(held, handler.ghostMinted(address(nft)), "tokens outside tracked recipients");
        }
    }

    /// @dev Per-call properties checked inside the handler (E-2, G-*)
    function invariant_handlerAssertions() public view {
        assertEq(handler.violations(), 0, handler.lastViolation());
    }

    /// @dev Require successful ETH and ERC-20 mints through both purchase paths.
    function test_successfulRegularAndSelectablePurchases() public {
        address regularNft = handler.nfts(0);
        address selectableNft = handler.nfts(1);

        vm.startPrank(handler.admin());
        stacks.configureDrop(
            regularNft,
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
                0,
                "ipfs://drop"
            )
        );
        stacks.configureDrop(
            selectableNft,
            Drop(
                DropType.SELECTABLE,
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
                0,
                "ipfs://drop"
            )
        );
        vm.stopPrank();

        handler.purchase(0, 0, 0, 1, 2);
        handler.purchaseSelected(1, 1, 1, 1, 2);
        assertEq(handler.successes("purchase"), 1, "regular purchase did not succeed");
        assertEq(handler.successes("purchaseSelected"), 1, "selectable purchase did not succeed");

        invariant_supplyConservation();
        invariant_selectableBitmap();
        invariant_noCustodyAndValueConservation();
        invariant_mintedTokensAccounted();
        invariant_handlerAssertions();
    }

    function _popcount(uint256 x) internal pure returns (uint256 count) {
        while (x != 0) {
            x &= x - 1;
            ++count;
        }
    }
}

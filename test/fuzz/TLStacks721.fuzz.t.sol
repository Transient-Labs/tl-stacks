// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {Drop} from "src/utils/TLStacks721Utils.sol";
import {DropPhase, DropType, DropErrors} from "src/utils/CommonUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {Merkle} from "test/utils/murky/Merkle.sol";

/// @dev Stateless fuzz tests for TLStacks721 boundaries and payment splits. IDs refer to docs/invariants.md.
contract TLStacks721FuzzTest is Test, DropErrors {
    uint256 constant BASIS = 10_000;

    TLStacks721 stacks;
    ERC721TL nft;
    MockERC20 coin;

    address admin = makeAddr("dropAdmin");
    address payout = makeAddr("payout");
    address feeReceiver = makeAddr("feeReceiver");
    address buyer = makeAddr("buyer");
    bytes32[] emptyProof;

    function setUp() public {
        vm.warp(1_000_000);
        stacks = new TLStacks721(address(this), address(0), feeReceiver, 0, 0, 0);
        coin = new MockERC20(address(this));
        stacks.setCurrencyAllowed(address(coin), true);

        address[] memory empty = new address[](0);
        address[] memory minters = new address[](1);
        minters[0] = address(stacks);
        nft = new ERC721TL(false);
        nft.initialize("Fuzz", "FUZZ", admin, 1_000, admin, empty, false, address(0), 0, address(0));
        vm.prank(admin);
        nft.setApprovedMintContracts(minters, true);

        vm.prank(buyer);
        coin.approve(address(stacks), type(uint256).max);
    }

    /////////////////////////////////////////////////////////////////////
    // PHASES
    /////////////////////////////////////////////////////////////////////

    /// @dev `getDropPhase` switches exactly at start, start + presale, and start + presale + public
    function testFuzz_phaseBoundaries(uint256 startDelay, uint256 presaleDuration, uint256 publicDuration) public {
        uint256 start = block.timestamp + bound(startDelay, 1, 365 days);
        presaleDuration = bound(presaleDuration, 0, 30 days);
        publicDuration = bound(publicDuration, 0, 30 days);
        _configure(DropType.REGULAR, 10, 10, address(0), start, presaleDuration, 0, publicDuration, 0, 0);
        uint256 publicStart = start + presaleDuration;
        uint256 end = publicStart + publicDuration;

        _assertPhaseAt(start - 1, DropPhase.NOT_STARTED);
        if (presaleDuration > 0) {
            _assertPhaseAt(start, DropPhase.PRESALE);
            _assertPhaseAt(publicStart - 1, DropPhase.PRESALE);
        }
        if (publicDuration > 0) {
            _assertPhaseAt(publicStart, DropPhase.PUBLIC_SALE);
            _assertPhaseAt(end - 1, DropPhase.PUBLIC_SALE);
        }
        _assertPhaseAt(end, DropPhase.ENDED);
    }

    /////////////////////////////////////////////////////////////////////
    // PAYMENTS
    /////////////////////////////////////////////////////////////////////

    /// @dev G-54 and E-2 on ETH drops: msg.value must be exactly price + flat fee per token, and the split is exact
    function testFuzz_ethPurchase_exactValueAndSplit(
        uint256 cost,
        uint256 numberToMint,
        uint256 protocolFee,
        uint256 bps,
        bool waived
    ) public {
        cost = bound(cost, 0, 10 ether);
        numberToMint = bound(numberToMint, 1, 20);
        protocolFee = bound(protocolFee, 0, 0.1 ether);
        bps = bound(bps, 0, stacks.MAX_SELLER_FEE_BPS());
        stacks.setProtocolFeeSettings(feeReceiver, protocolFee, bps, 0);
        if (waived) stacks.waiveSellerFee(address(nft));
        _configure(DropType.REGULAR, 20, 20, address(0), block.timestamp, 0, 0, 1 days, cost, 0);

        uint256 value = numberToMint * (cost + protocolFee);
        vm.deal(buyer, value + 1);
        if (value > 0) {
            _expectPurchaseRevert(IncorrectFunds.selector, numberToMint, value - 1, address(0), cost, 0);
        }
        _expectPurchaseRevert(IncorrectFunds.selector, numberToMint, value + 1, address(0), cost, 0);

        vm.prank(buyer);
        stacks.purchase{value: value}(address(nft), buyer, numberToMint, 0, emptyProof, address(0), cost, 0);

        uint256 sellerFee = waived ? 0 : numberToMint * cost * bps / BASIS;
        assertEq(payout.balance, numberToMint * cost - sellerFee, "E-2: payout receiver");
        assertEq(feeReceiver.balance, sellerFee + numberToMint * protocolFee, "E-2: fee receiver");
        assertGe(payout.balance * BASIS, numberToMint * cost * (BASIS - stacks.MAX_SELLER_FEE_BPS()), "E-2: >= 95%");
        assertEq(address(stacks).balance, 0, "stacks kept ETH");
        assertEq(nft.balanceOf(buyer), numberToMint);
    }

    /// @dev E-2 and E-3 on ERC-20 drops: no ETH may be sent, the flat protocol fee is not charged, and the split is
    ///      exact
    function testFuzz_erc20Purchase_noEthAndSplit(
        uint256 cost,
        uint256 numberToMint,
        uint256 bps,
        bool waived,
        uint256 ethSent
    ) public {
        cost = bound(cost, 0, 1_000 ether);
        numberToMint = bound(numberToMint, 1, 20);
        bps = bound(bps, 0, stacks.MAX_SELLER_FEE_BPS());
        ethSent = bound(ethSent, 1, 1 ether);
        stacks.setProtocolFeeSettings(feeReceiver, 0.01 ether, 0, bps);
        if (waived) stacks.waiveSellerFee(address(nft));
        _configure(DropType.REGULAR, 20, 20, address(coin), block.timestamp, 0, 0, 1 days, cost, 0);
        coin.transfer(buyer, numberToMint * cost);

        vm.deal(buyer, ethSent);
        _expectPurchaseRevert(IncorrectFunds.selector, numberToMint, ethSent, address(coin), cost, 0);

        vm.prank(buyer);
        stacks.purchase(address(nft), buyer, numberToMint, 0, emptyProof, address(coin), cost, 0);

        uint256 sellerFee = waived ? 0 : numberToMint * cost * bps / BASIS;
        assertEq(coin.balanceOf(payout), numberToMint * cost - sellerFee, "E-2: payout receiver");
        assertEq(coin.balanceOf(feeReceiver), sellerFee, "E-2: fee receiver");
        assertEq(feeReceiver.balance, 0, "E-3: flat fee charged on an ERC-20 drop");
        assertEq(coin.balanceOf(buyer), 0);
    }

    /// @dev Buyer pins: max cost per token is inclusive, and a currency or round mismatch reverts
    function testFuzz_buyerPins(uint256 cost) public {
        cost = bound(cost, 1, 10 ether);
        _configure(DropType.REGULAR, 20, 20, address(0), block.timestamp, 0, 0, 1 days, cost, 0);
        vm.deal(buyer, 10 * cost);

        _expectPurchaseRevert(PriceTooHigh.selector, 1, cost, address(0), cost - 1, 0);
        _expectPurchaseRevert(CurrencyMismatch.selector, 1, cost, address(coin), cost, 0);
        _expectPurchaseRevert(DropRoundChanged.selector, 1, cost, address(0), cost, 1);

        vm.prank(buyer);
        stacks.purchase{value: cost}(address(nft), buyer, 1, 0, emptyProof, address(0), cost, 0);
        assertEq(nft.balanceOf(buyer), 1);
    }

    /////////////////////////////////////////////////////////////////////
    // VELOCITY
    /////////////////////////////////////////////////////////////////////

    /// @dev Each velocity mint moves the public duration by decayRate * numberToMint, saturating at zero
    function testFuzz_velocityDecay(int256 decayRate, uint256 publicDuration, uint256 numberToMint) public {
        decayRate = bound(decayRate, -1 days, 1 days);
        publicDuration = bound(publicDuration, 1, 30 days);
        numberToMint = bound(numberToMint, 1, 10);
        _configure(DropType.VELOCITY, 100, 100, address(0), block.timestamp, 0, 0, publicDuration, 0, decayRate);

        vm.prank(buyer);
        stacks.purchase(address(nft), buyer, numberToMint, 0, emptyProof, address(0), 0, 0);

        uint256 adjust = uint256(decayRate < 0 ? -decayRate : decayRate) * numberToMint;
        uint256 expected =
            decayRate < 0 ? (adjust > publicDuration ? 0 : publicDuration - adjust) : publicDuration + adjust;
        assertEq(stacks.getDrop(address(nft)).publicDuration, expected);
        if (expected == 0) assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(DropPhase.ENDED));
    }

    /// @dev The saturation boundary exactly: a negative adjustment of publicDuration - 1, publicDuration, or
    ///      publicDuration + 1 leaves 1, 0, and 0
    function testFuzz_velocitySaturationBoundary(uint256 publicDuration, uint256 offsetSeed) public {
        publicDuration = bound(publicDuration, 2, 30 days);
        uint256 adjust = publicDuration - 1 + offsetSeed % 3;
        _configure(DropType.VELOCITY, 100, 100, address(0), block.timestamp, 0, 0, publicDuration, 0, -int256(adjust));

        vm.prank(buyer);
        stacks.purchase(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);
        assertEq(stacks.getDrop(address(nft)).publicDuration, adjust >= publicDuration ? 0 : 1);
    }

    /////////////////////////////////////////////////////////////////////
    // PRESALE
    /////////////////////////////////////////////////////////////////////

    /// @dev The presale leaf binds recipient and count; presale and public allowances are tracked separately
    function testFuzz_presaleMerkle(uint256[4] memory allowances, uint256 who, uint256 claimed, uint256 publicAllowance)
        public
    {
        address[4] memory accounts = [buyer, makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
        Merkle merkle = new Merkle();
        bytes32[] memory leaves = new bytes32[](4);
        for (uint256 i = 0; i < 4; ++i) {
            allowances[i] = bound(allowances[i], 1, 10);
            leaves[i] =
                keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(accounts[i])), allowances[i]))));
        }
        who = bound(who, 0, 3);
        publicAllowance = bound(publicAllowance, 1, 10);
        address recipient = accounts[who];
        bytes32[] memory proof = merkle.getProof(leaves, who);

        uint256 start = block.timestamp;
        _configureWithRoot(merkle.getRoot(leaves), start, 1 days, publicAllowance);

        // the wrong count or the wrong recipient doesn't verify
        claimed = bound(claimed, 0, 20);
        if (claimed != allowances[who]) {
            vm.prank(buyer);
            vm.expectRevert(NotOnAllowlist.selector);
            stacks.purchase(address(nft), recipient, 1, claimed, proof, address(0), 0, 0);
        }
        vm.prank(buyer);
        vm.expectRevert(NotOnAllowlist.selector);
        stacks.purchase(address(nft), accounts[(who + 1) % 4], 1, allowances[who], proof, address(0), 0, 0);

        // the leaf's count is the presale cap
        vm.startPrank(buyer);
        stacks.purchase(address(nft), recipient, allowances[who], allowances[who], proof, address(0), 0, 0);
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        stacks.purchase(address(nft), recipient, 1, allowances[who], proof, address(0), 0, 0);

        // the public allowance is separate from what was minted in presale
        vm.warp(start + 1 days);
        stacks.purchase(address(nft), recipient, publicAllowance, 0, emptyProof, address(0), 0, 0);
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        stacks.purchase(address(nft), recipient, 1, 0, emptyProof, address(0), 0, 0);
        vm.stopPrank();

        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(address(nft), recipient);
        assertEq(presaleMinted, allowances[who]);
        assertEq(publicMinted, publicAllowance);
    }

    /////////////////////////////////////////////////////////////////////
    // SELECTABLE
    /////////////////////////////////////////////////////////////////////

    /// @dev G-56 and G-57: out of range, repeated within a call, and already minted indices all revert, and the
    ///      purchase functions can't be mixed up across drop types
    function testFuzz_selectableIndexGuards(uint256 supply, uint256 index, uint256 outOfRange) public {
        supply = bound(supply, 1, 500);
        index = bound(index, 0, supply - 1);
        outOfRange = bound(outOfRange, supply, type(uint256).max);
        _configure(DropType.SELECTABLE, supply, 10, address(0), block.timestamp, 0, 0, 1 days, 0, 0);

        vm.startPrank(buyer);
        vm.expectRevert(IndexOutOfRange.selector);
        stacks.purchaseSelected(address(nft), buyer, _indices(outOfRange), 0, emptyProof, address(0), 0, 0);

        if (supply > 1) {
            uint256[] memory repeated = new uint256[](2);
            (repeated[0], repeated[1]) = (index, index);
            vm.expectRevert(IndexAlreadyMinted.selector);
            stacks.purchaseSelected(address(nft), buyer, repeated, 0, emptyProof, address(0), 0, 0);
        }

        vm.expectRevert(NotAllowedForSelectableDrops.selector);
        stacks.purchase(address(nft), buyer, 1, 0, emptyProof, address(0), 0, 0);

        stacks.purchaseSelected(address(nft), buyer, _indices(index), 0, emptyProof, address(0), 0, 0);
        assertTrue(stacks.isIndexMinted(address(nft), index));
        assertEq(nft.tokenURI(1), string.concat("ipfs://drop/", vm.toString(index)));

        // with a supply of one, the first mint sold out the drop, so the phase check fires first
        vm.expectRevert(supply > 1 ? IndexAlreadyMinted.selector : YouShallNotMint.selector);
        stacks.purchaseSelected(address(nft), buyer, _indices(index), 0, emptyProof, address(0), 0, 0);
        vm.stopPrank();

        // a regular drop rejects purchaseSelected
        vm.prank(admin);
        stacks.closeDrop(address(nft));
        _configure(DropType.REGULAR, supply, 10, address(0), block.timestamp, 0, 0, 1 days, 0, 0);
        vm.prank(buyer);
        vm.expectRevert(NotSelectableDrop.selector);
        stacks.purchaseSelected(address(nft), buyer, _indices(index), 0, emptyProof, address(0), 0, 1);
    }

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _configure(
        DropType dropType,
        uint256 supply,
        uint256 allowance,
        address currency,
        uint256 start,
        uint256 presaleDuration,
        uint256 presaleCost,
        uint256 publicDuration,
        uint256 publicCost,
        int256 decayRate
    ) internal {
        Drop memory drop = Drop(
            dropType,
            payout,
            supply,
            supply,
            allowance,
            currency,
            start,
            presaleDuration,
            presaleCost,
            bytes32(0),
            publicDuration,
            publicCost,
            decayRate,
            "ipfs://drop"
        );
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
    }

    function _configureWithRoot(bytes32 root, uint256 start, uint256 presaleDuration, uint256 allowance) internal {
        Drop memory drop = Drop(
            DropType.REGULAR,
            payout,
            100,
            100,
            allowance,
            address(0),
            start,
            presaleDuration,
            0,
            root,
            1 days,
            0,
            0,
            "ipfs://drop"
        );
        vm.prank(admin);
        stacks.configureDrop(address(nft), drop);
    }

    function _expectPurchaseRevert(
        bytes4 selector,
        uint256 numberToMint,
        uint256 value,
        address currency,
        uint256 maxCost,
        uint256 round
    ) internal {
        vm.prank(buyer);
        vm.expectRevert(selector);
        stacks.purchase{value: value}(address(nft), buyer, numberToMint, 0, emptyProof, currency, maxCost, round);
    }

    function _assertPhaseAt(uint256 timestamp, DropPhase expected) internal {
        vm.warp(timestamp);
        assertEq(uint8(stacks.getDropPhase(address(nft))), uint8(expected), "phase");
    }

    function _indices(uint256 index) internal pure returns (uint256[] memory indices) {
        indices = new uint256[](1);
        indices[0] = index;
    }
}

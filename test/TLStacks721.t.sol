// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {IERC20Errors} from "openzeppelin/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {ERC721TL} from "tl-creator-contracts/erc-721/ERC721TL.sol";
import {WETH9} from "tl-sol-tools/../test/utils/WETH9.sol";
import {IChainalysisSanctionsOracle, SanctionsCompliance} from "tl-sol-tools/payments/SanctionsCompliance.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {ITLStacks721Events, Drop} from "src/utils/TLStacks721Utils.sol";
import {DropPhase, DropType, DropErrors} from "src/utils/CommonUtils.sol";
import {Receiver} from "test/utils/Receiver.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

contract TLStacks721Test is Test, ITLStacks721Events, DropErrors {
    using Strings for uint256;

    bytes32 constant MINTER_ROLE = keccak256("APPROVED_MINT_CONTRACT");
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address wethAddress;
    TLStacks721 stacks;
    ERC721TL nft;
    ERC721TL nftTwo;
    MockERC20 coin;

    bytes32[] emptyProof = new bytes32[](0);

    address nftOwner = address(0xABC);
    address receiver;

    address tl = makeAddr("Build Different");
    uint256 fee = 0.00042 ether;
    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);
    address bsy = address(0xCDB);
    address minter = address(0x12345);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        wethAddress = address(new WETH9());
        stacks = new TLStacks721(address(0), wethAddress, tl, fee);

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(stacks);

        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", "", nftOwner, 1_000, nftOwner, empty, false, address(0), address(0));
        vm.prank(nftOwner);
        nft.setApprovedMintContracts(mintAddrs, true);

        coin = new MockERC20(address(this));
        coin.transfer(ben, 100 ether);
        coin.transfer(chris, 100 ether);
        coin.transfer(david, 100 ether);
        coin.transfer(bsy, 100 ether);
        coin.transfer(minter, 100 ether);

        receiver = address(new Receiver());

        vm.deal(ben, 100 ether);
        vm.deal(chris, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(bsy, 100 ether);
        vm.deal(minter, 100 ether);

        nftTwo = new ERC721TL(false);
        nftTwo.initialize("Test ERC721 2", "LFG2", "", nftOwner, 1_000, nftOwner, empty, false, address(0), address(0));
        vm.prank(nftOwner);
        nftTwo.setApprovedMintContracts(mintAddrs, true);
    }

    /// @dev test constructor setup
    function test_setUp() public {
        assertEq(stacks.owner(), address(this));
        assertEq(stacks.weth(), wethAddress);
        assertEq(stacks.protocolFeeReceiver(), tl);
        assertEq(stacks.protocolFee(), fee);
        assertFalse(stacks.paused());
        assertTrue(nft.hasRole(MINTER_ROLE, address(stacks)));
    }

    /// @dev test owner only access for owner functions
    /// @dev reverts if not the owner
    function test_ownerOnlyAccess(address sender) public {
        vm.assume(sender != address(this));

        // revert for sender (non-owner)
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.pause(true);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.pause(false);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.transferOwnership(sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.setWethAddress(address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.setProtocolFeeSettings(sender, 1 ether);
        vm.stopPrank();

        // pass for owner
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), address(this));
        stacks.transferOwnership(address(this));
        vm.expectEmit(true, true, false, false);
        emit WethUpdated(wethAddress, address(0));
        stacks.setWethAddress(address(0));
        assertEq(stacks.weth(), address(0));
        vm.expectEmit(true, true, false, false);
        emit ProtocolFeeUpdated(address(0), 0);
        stacks.setProtocolFeeSettings(address(0), 0);
        assertEq(stacks.protocolFeeReceiver(), address(0));
        assertEq(stacks.protocolFee(), 0);
        vm.expectEmit(false, false, false, true);
        emit Paused(address(this));
        stacks.pause(true);
        vm.expectEmit(false, false, false, true);
        emit Unpaused(address(this));
        stacks.pause(false);
    }

    /// @dev test that pausing the contract blocks all applicable functions
    function test_paused() public {
        stacks.pause(true);

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );

        vm.startPrank(nftOwner);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.configureDrop(address(nft), drop);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropPayoutReceiver(address(nft), address(this));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropAllowance(address(nft), 10);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropPrices(address(nft), address(0), 0, 0.5 ether);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(0));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropDecayRate(address(nft), -1);
        vm.stopPrank();
    }

    /// @dev test that drop admins or contract owner can access drop write functions
    /// @dev reverts when `notDropAdmin` calls the functions
    function test_dropAdminAccess(address dropAdmin, address notDropAdmin) public {
        vm.assume(dropAdmin != nftOwner);
        vm.assume(notDropAdmin != nftOwner);
        vm.assume(dropAdmin != notDropAdmin);

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );

        // test contract owner
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        stacks.updateDropPayoutReceiver(address(nft), address(this));
        stacks.updateDropAllowance(address(nft), 10);
        stacks.updateDropPrices(address(nft), address(0), 0, 0.5 ether);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(0));
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
        stacks.updateDropDecayRate(address(nft), -1);
        stacks.closeDrop(address(nft));
        address[] memory admins = new address[](1);
        admins[0] = dropAdmin;
        nft.setRole(ADMIN_ROLE, admins, true);
        vm.stopPrank();

        // test contract admin
        vm.startPrank(dropAdmin);
        stacks.configureDrop(address(nft), drop);
        stacks.updateDropPayoutReceiver(address(nft), address(this));
        stacks.updateDropAllowance(address(nft), 10);
        stacks.updateDropPrices(address(nft), address(0), 0, 0.5 ether);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(0));
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
        stacks.updateDropDecayRate(address(nft), -1);
        stacks.closeDrop(address(nft));
        nft.renounceRole(ADMIN_ROLE);
        vm.stopPrank();

        // test not admin or contract owner
        vm.startPrank(notDropAdmin);
        vm.expectRevert(NotDropAdmin.selector);
        stacks.configureDrop(address(nft), drop);
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropPayoutReceiver(address(nft), address(this));
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropAllowance(address(nft), 10);
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropPrices(address(nft), address(0), 0, 0.5 ether);
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(0));
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropDecayRate(address(nft), -1);
        vm.expectRevert(NotDropAdmin.selector);
        stacks.closeDrop(address(nft));
        vm.stopPrank();
    }

    /// @dev test that updating drops does not work if the drop is not configured
    function test_updateDropsNotConfigured() public {
        vm.startPrank(nftOwner);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPayoutReceiver(address(nft), address(this));
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropAllowance(address(nft), 10);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPrices(address(nft), address(0), 0, 0.5 ether);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(0));
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDecayRate(address(nft), -1);
        vm.stopPrank();
    }

    /// @dev test configureDrop errors
    function test_configureDropErrors() public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            address(0),
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );

        vm.startPrank(nftOwner);

        // payout to zero address
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.configureDrop(address(nft), drop);
        // mismatch supply
        drop.payoutReceiver = nftOwner;
        drop.supply = 9;
        vm.expectRevert(InvalidDropSupply.selector);
        stacks.configureDrop(address(nft), drop);
        // invalid drop type (velocity)
        drop.supply = 10;
        drop.decayRate = -1;
        vm.expectRevert(InvalidDropType.selector);
        stacks.configureDrop(address(nft), drop);
        // invalid drop type (marathon)
        drop.decayRate = 1;
        vm.expectRevert(InvalidDropType.selector);
        stacks.configureDrop(address(nft), drop);
        // not allowed for velocity mint (velocity)
        drop.decayRate = -1;
        drop.dropType = DropType.VELOCITY;
        drop.presaleDuration = 1000;
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
        stacks.configureDrop(address(nft), drop);
        // not allowed for velocity mint (marathon)
        drop.decayRate = 1;
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
        stacks.configureDrop(address(nft), drop);
        // drop already configured
        drop.presaleDuration = 0;
        stacks.configureDrop(address(nft), drop);
        vm.expectRevert(DropAlreadyConfigured.selector);
        stacks.configureDrop(address(nft), drop);

        address[] memory mintContracts = new address[](1);
        mintContracts[0] = address(stacks);
        nft.setApprovedMintContracts(mintContracts, false);
        vm.expectRevert(NotApprovedMintContract.selector);
        stacks.configureDrop(address(nft), drop);

        vm.stopPrank();
    }

    /// @dev test regular drop configuration
    function test_configureDropRegular(
        uint256 supply,
        uint256 allowance,
        bool useEth,
        uint256 presaleDuration,
        uint256 presaleCost,
        bytes32 presaleMerkleRoot,
        uint256 publicDuration,
        uint256 publicCost,
        string memory baseUri
    ) public {
        address currencyAddress = useEth ? address(0) : address(coin);
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            supply,
            supply,
            allowance,
            currencyAddress,
            block.timestamp,
            presaleDuration,
            presaleCost,
            presaleMerkleRoot,
            publicDuration,
            publicCost,
            0,
            baseUri
        );

        vm.expectEmit(true, true, false, true);
        emit DropConfigured(address(nft), drop);
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.dropType == drop.dropType);
        assert(retreivedDrop.payoutReceiver == drop.payoutReceiver);
        assert(retreivedDrop.initialSupply == drop.initialSupply);
        assert(retreivedDrop.supply == drop.supply);
        assert(retreivedDrop.allowance == drop.allowance);
        assert(retreivedDrop.currencyAddress == drop.currencyAddress);
        assert(retreivedDrop.startTime == drop.startTime);
        assert(retreivedDrop.presaleDuration == drop.presaleDuration);
        assert(retreivedDrop.presaleCost == drop.presaleCost);
        assert(retreivedDrop.presaleMerkleRoot == drop.presaleMerkleRoot);
        assert(retreivedDrop.publicDuration == drop.publicDuration);
        assert(retreivedDrop.publicCost == drop.publicCost);
        assert(retreivedDrop.decayRate == drop.decayRate);
        assert(keccak256(bytes(retreivedDrop.baseUri)) == keccak256(bytes(drop.baseUri)));
        assert(stacks.getDropRound(address(nft)) == 0);
    }

    /// @dev test velocity drop configuration
    function test_configureDropVelocity(
        uint256 supply,
        uint256 allowance,
        bool useEth,
        uint256 publicDuration,
        uint256 publicCost,
        int256 decayRate,
        string memory baseUri
    ) public {
        address currencyAddress = useEth ? address(0) : address(coin);
        Drop memory drop = Drop(
            DropType.VELOCITY,
            nftOwner,
            supply,
            supply,
            allowance,
            currencyAddress,
            block.timestamp,
            0,
            0,
            bytes32(0),
            publicDuration,
            publicCost,
            decayRate,
            baseUri
        );

        vm.expectEmit(true, true, false, true);
        emit DropConfigured(address(nft), drop);
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.dropType == drop.dropType);
        assert(retreivedDrop.payoutReceiver == drop.payoutReceiver);
        assert(retreivedDrop.initialSupply == drop.initialSupply);
        assert(retreivedDrop.supply == drop.supply);
        assert(retreivedDrop.allowance == drop.allowance);
        assert(retreivedDrop.currencyAddress == drop.currencyAddress);
        assert(retreivedDrop.startTime == drop.startTime);
        assert(retreivedDrop.presaleDuration == drop.presaleDuration);
        assert(retreivedDrop.presaleCost == drop.presaleCost);
        assert(retreivedDrop.presaleMerkleRoot == drop.presaleMerkleRoot);
        assert(retreivedDrop.publicDuration == drop.publicDuration);
        assert(retreivedDrop.publicCost == drop.publicCost);
        assert(retreivedDrop.decayRate == drop.decayRate);
        assert(keccak256(bytes(retreivedDrop.baseUri)) == keccak256(bytes(drop.baseUri)));
        assert(stacks.getDropRound(address(nft)) == 0);
    }

    /// @dev test updating drop payout receiver functionality and errors
    function test_updateDropPayoutReceiver(address payoutReceiver) public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        // configure drop
        stacks.configureDrop(address(nft), drop);
        // invalid payout receiver
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.updateDropPayoutReceiver(address(nft), address(0));
        // update
        if (payoutReceiver == address(0)) {
            vm.expectRevert(InvalidPayoutReceiver.selector);
            stacks.updateDropPayoutReceiver(address(nft), payoutReceiver);
        } else {
            drop.payoutReceiver = payoutReceiver;
            vm.expectEmit(true, true, false, true);
            emit DropUpdated(address(nft), drop);
            stacks.updateDropPayoutReceiver(address(nft), payoutReceiver);

            Drop memory retreivedDrop = stacks.getDrop(address(nft));
            assert(retreivedDrop.payoutReceiver == payoutReceiver);
        }
        // warp to end of drop
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPayoutReceiver(address(nft), payoutReceiver);

        vm.stopPrank();
    }

    /// @dev test updating drop allowance
    function test_updateDropAllowance(uint256 allowance) public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        // configure drop
        stacks.configureDrop(address(nft), drop);
        // update
        drop.allowance = allowance;
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropAllowance(address(nft), allowance);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.allowance == allowance);

        // warp to end of drop
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropAllowance(address(nft), allowance);

        vm.stopPrank();
    }

    /// @dev test updating drop prices
    function test_updateDropPrices(address currencyAddress, uint256 presaleCost, uint256 publicCost) public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        drop.currencyAddress = currencyAddress;
        drop.presaleCost = presaleCost;
        drop.publicCost = publicCost;
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropPrices(address(nft), currencyAddress, presaleCost, publicCost);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.currencyAddress == currencyAddress);
        assert(retreivedDrop.presaleCost == presaleCost);
        assert(retreivedDrop.publicCost == publicCost);

        // warp to end of drop
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPrices(address(nft), currencyAddress, presaleCost, publicCost);

        vm.stopPrank();
    }

    /// @dev test updating regular drop durations
    function test_updateDropDurationRegular(uint256 startTime, uint256 presaleDuration, uint256 publicDuration)
        public
    {
        if (startTime > type(uint64).max) startTime = startTime % type(uint64).max;
        if (presaleDuration > type(uint64).max) presaleDuration = presaleDuration % type(uint64).max;
        if (publicDuration > type(uint64).max) publicDuration = publicDuration % type(uint64).max;

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        // drop not configured
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
        stacks.configureDrop(address(nft), drop);
        drop.startTime = startTime;
        drop.presaleDuration = presaleDuration;
        drop.publicDuration = publicDuration;
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.startTime == startTime);
        assert(retreivedDrop.presaleDuration == presaleDuration);
        assert(retreivedDrop.publicDuration == publicDuration);

        // warp to end of drop
        vm.warp(startTime + presaleDuration + publicDuration + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);

        vm.stopPrank();

        // test not drop admin
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
    }

    /// @dev test updating velocity drop durations
    function test_updateDropDurationVelocity(uint256 startTime, uint256 presaleDuration, uint256 publicDuration)
        public
    {
        if (startTime > type(uint64).max) startTime = startTime % type(uint64).max;
        if (presaleDuration > type(uint64).max) presaleDuration = presaleDuration % type(uint64).max;
        if (publicDuration > type(uint64).max) publicDuration = publicDuration % type(uint64).max;

        Drop memory drop = Drop(
            DropType.VELOCITY,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            -1,
            "https://arweave.net/abc"
        );

        vm.startPrank(nftOwner);
        // drop not configured
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
        stacks.configureDrop(address(nft), drop);
        if (presaleDuration != 0) {
            vm.expectRevert(NotAllowedForVelocityDrops.selector);
            stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
        } else {
            drop.startTime = startTime;
            drop.presaleDuration = presaleDuration;
            drop.publicDuration = publicDuration;
            vm.expectEmit(true, true, false, true);
            emit DropUpdated(address(nft), drop);
            stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);

            Drop memory retreivedDrop = stacks.getDrop(address(nft));
            assert(retreivedDrop.startTime == startTime);
            assert(retreivedDrop.presaleDuration == presaleDuration);
            assert(retreivedDrop.publicDuration == publicDuration);

            // warp to end of drop
            vm.warp(startTime + publicDuration + 1000);
            vm.expectRevert(DropUpdateNotAllowed.selector);
            stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
        }
        vm.stopPrank();

        // test not drop admin
        vm.expectRevert(NotDropAdmin.selector);
        stacks.updateDropDuration(address(nft), startTime, presaleDuration, publicDuration);
    }

    /// @dev test updating drop merkle root
    function test_updateDropPresaleMerkleRoot(bytes32 presaleMerkleRoot) public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            1000,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        drop.presaleMerkleRoot = presaleMerkleRoot;
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropPresaleMerkleRoot(address(nft), presaleMerkleRoot);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.presaleMerkleRoot == presaleMerkleRoot);

        // warp to end of drop
        vm.warp(block.timestamp + 10000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropPresaleMerkleRoot(address(nft), presaleMerkleRoot);

        vm.stopPrank();
    }

    /// @dev test updating drop decay rate errors
    function test_updateDropDecayRateRegular(int256 decayRate) public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
        stacks.updateDropDecayRate(address(nft), decayRate);

        // warp to end of drop
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDecayRate(address(nft), decayRate);

        vm.stopPrank();
    }

    /// @dev test updating drop decay rate
    function test_updateDropDecayRate(int256 decayRate) public {
        Drop memory drop = Drop(
            DropType.VELOCITY,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            -1,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        drop.decayRate = decayRate;
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropDecayRate(address(nft), decayRate);

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.decayRate == decayRate);

        // warp to end of drop
        vm.warp(block.timestamp + 1000);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropDecayRate(address(nft), decayRate);

        vm.stopPrank();
    }

    /// @dev test closing a drop
    function test_closeDrop() public {
        uint256 prevRound = stacks.getDropRound(address(nft));
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        vm.expectEmit(true, true, false, false);
        emit DropClosed(address(nft));
        stacks.closeDrop(address(nft));

        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.dropType == DropType.NOT_CONFIGURED);
        assert(retreivedDrop.payoutReceiver == address(0));
        assert(retreivedDrop.initialSupply == 0);
        assert(retreivedDrop.supply == 0);
        assert(retreivedDrop.allowance == 0);
        assert(retreivedDrop.currencyAddress == address(0));
        assert(retreivedDrop.startTime == 0);
        assert(retreivedDrop.presaleDuration == 0);
        assert(retreivedDrop.presaleCost == 0);
        assert(retreivedDrop.presaleMerkleRoot == bytes32(0));
        assert(retreivedDrop.publicDuration == 0);
        assert(retreivedDrop.publicCost == 0);
        assert(retreivedDrop.decayRate == 0);
        assert(keccak256(bytes(retreivedDrop.baseUri)) == keccak256(bytes("")));
        assert(stacks.getDropRound(address(nft)) == prevRound + 1);
    }

    /// @dev test drop ended and re-configure
    function test_configureDrop_afterPrevDropEnds() public {
        // set drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // check drop
        Drop memory retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.dropType == DropType.REGULAR);
        assert(retreivedDrop.payoutReceiver == nftOwner);
        assert(retreivedDrop.initialSupply == 10);
        assert(retreivedDrop.supply == 10);
        assert(retreivedDrop.allowance == 1);
        assert(retreivedDrop.currencyAddress == address(0));
        assert(retreivedDrop.startTime == block.timestamp);
        assert(retreivedDrop.presaleDuration == 0);
        assert(retreivedDrop.presaleCost == 0);
        assert(retreivedDrop.presaleMerkleRoot == bytes32(0));
        assert(retreivedDrop.publicDuration == 1000);
        assert(retreivedDrop.publicCost == 1 ether);
        assert(retreivedDrop.decayRate == 0);
        assert(keccak256(bytes(retreivedDrop.baseUri)) == keccak256(bytes("https://arweave.net/abc")));
        assert(stacks.getDropRound(address(nft)) == 0);

        // warp to end and ensure closed
        vm.warp(block.timestamp + 10000);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);

        // set drop again
        drop.supply = 20;
        drop.initialSupply = 20;
        drop.startTime = block.timestamp;
        stacks.configureDrop(address(nft), drop);

        // check drop
        retreivedDrop = stacks.getDrop(address(nft));
        assert(retreivedDrop.dropType == DropType.REGULAR);
        assert(retreivedDrop.payoutReceiver == nftOwner);
        assert(retreivedDrop.initialSupply == 20);
        assert(retreivedDrop.supply == 20);
        assert(retreivedDrop.allowance == 1);
        assert(retreivedDrop.currencyAddress == address(0));
        assert(retreivedDrop.startTime == block.timestamp);
        assert(retreivedDrop.presaleDuration == 0);
        assert(retreivedDrop.presaleCost == 0);
        assert(retreivedDrop.presaleMerkleRoot == bytes32(0));
        assert(retreivedDrop.publicDuration == 1000);
        assert(retreivedDrop.publicCost == 1 ether);
        assert(retreivedDrop.decayRate == 0);
        assert(keccak256(bytes(retreivedDrop.baseUri)) == keccak256(bytes("https://arweave.net/abc")));
        assert(stacks.getDropRound(address(nft)) == 1);

        vm.stopPrank();
    }

    /// @dev test drop phase calculation
    function test_getDropPhase() public {
        vm.startPrank(nftOwner);

        // not configured
        DropPhase dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.NOT_CONFIGURED);

        // not started -> presale -> public -> ended
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp + 1000,
            1000,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        stacks.configureDrop(address(nft), drop);
        dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.NOT_STARTED);
        vm.warp(block.timestamp + 1000);
        dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.PRESALE);
        vm.warp(block.timestamp + 1000);
        dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.PUBLIC_SALE);
        vm.warp(block.timestamp + 1000);
        dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.ENDED);
        stacks.closeDrop(address(nft));

        // ended based on 0 supply
        drop.supply = 0;
        drop.initialSupply = 0;
        stacks.configureDrop(address(nft), drop);
        dropPhase = stacks.getDropPhase(address(nft));
        assert(dropPhase == DropPhase.ENDED);
    }

    /// @dev test purchase with eth errors
    function test_purchaseEthErrors() public {
        // merkle tree
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1)));
        data[1] = keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3)));
        data[2] = keccak256(abi.encode(keccak256(abi.encode(david)), uint256(4)));
        data[3] = keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(5)));
        bytes32 root = m.getRoot(data);

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            2,
            2,
            1,
            address(0),
            block.timestamp,
            1000,
            0.1 ether,
            root,
            1000,
            0,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // mint zero tokens
        bytes32[] memory proof = m.getProof(data, 0);
        vm.expectRevert(MintZeroTokens.selector);
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 0, 1, proof);

        // not on allowlist
        vm.expectRevert(NotOnAllowlist.selector);
        vm.prank(minter);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), minter, 1, 1, emptyProof);

        // reached mint allowance
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 1, 1, proof);
        vm.expectRevert(AlreadyReachedMintAllowance.selector);
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 1, 1, proof);

        // insufficent funds
        proof = m.getProof(data, 1);
        vm.expectRevert(InsufficientFunds.selector);
        vm.prank(chris);
        stacks.purchase{value: 0.1 ether}(address(nft), chris, 1, 3, proof);
    }

    /// @dev test purchase with erc20 errors
    function test_purchaseERC20Errors() public {
        // merkle tree
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1)));
        data[1] = keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3)));
        data[2] = keccak256(abi.encode(keccak256(abi.encode(david)), uint256(4)));
        data[3] = keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(5)));
        bytes32 root = m.getRoot(data);

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            2,
            2,
            1,
            address(coin),
            block.timestamp,
            1000,
            0.1 ether,
            root,
            1000,
            0,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // mint zero tokens
        bytes32[] memory proof = m.getProof(data, 0);
        vm.expectRevert(MintZeroTokens.selector);
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 0, 1, proof);

        // not on allowlist
        vm.expectRevert(NotOnAllowlist.selector);
        vm.prank(minter);
        stacks.purchase{value: fee}(address(nft), minter, 1, 1, emptyProof);

        // reached mint allowance
        vm.prank(ben);
        coin.approve(address(stacks), 1 ether);
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 1, proof);
        vm.expectRevert(AlreadyReachedMintAllowance.selector);
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 1, proof);

        // insufficent fee
        proof = m.getProof(data, 1);
        vm.expectRevert(InsufficientFunds.selector);
        vm.prank(chris);
        stacks.purchase(address(nft), chris, 1, 3, proof);

        // not enough erc20 allowance given
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(stacks), 0, 0.1 ether)
        );
        vm.prank(chris);
        stacks.purchase{value: fee}(address(nft), chris, 1, 3, proof);

        // not enough erc20 balance
        vm.prank(chris);
        coin.transfer(ben, 100 ether);
        vm.prank(chris);
        coin.approve(address(stacks), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether));
        vm.prank(chris);
        stacks.purchase{value: fee}(address(nft), chris, 1, 3, proof);
    }

    /// @dev test refund logic eth
    function test_refundLogicEth(uint256 extra) public {
        if (extra > 98 ether) {
            extra = extra % 98 ether;
        }

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            2,
            2,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        uint256 prevBenBalance = ben.balance;
        uint256 prevNftOwnerBalance = nftOwner.balance;
        uint256 prevTLBalance = tl.balance;
        vm.prank(ben);
        uint256 refundAmount = stacks.purchase{value: 1 ether + extra + fee}(address(nft), ben, 1, 0, emptyProof);
        assert(prevBenBalance - ben.balance == 1 ether + fee);
        assert(nftOwner.balance - prevNftOwnerBalance == 1 ether);
        assert(tl.balance - prevTLBalance == fee);
        assert(refundAmount == extra);
    }

    /// @dev test refund logic erc20
    function test_refundLogicERC20(uint256 extra) public {
        if (extra > 98 ether) {
            extra = extra % 98 ether;
        }

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            2,
            2,
            1,
            address(coin),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        vm.prank(ben);
        coin.approve(address(stacks), 1 ether);

        uint256 prevBenBalance = ben.balance;
        uint256 prevBenCoinBalance = coin.balanceOf(ben);
        uint256 prevNftOwnerBalance = coin.balanceOf(nftOwner);
        uint256 prevTLBalance = tl.balance;
        vm.prank(ben);
        uint256 refundAmount = stacks.purchase{value: extra + fee}(address(nft), ben, 1, 0, emptyProof);
        assert(prevBenBalance - ben.balance == fee);
        assert(prevBenCoinBalance - coin.balanceOf(ben) == 1 ether);
        assert(coin.balanceOf(nftOwner) - prevNftOwnerBalance == 1 ether);
        assert(tl.balance - prevTLBalance == fee);
        assert(refundAmount == extra);
    }

    /// @dev test purchase for another address eth
    function test_purchaseForSomeoneElseEth(address sender, address recipient) public {
        vm.assume(sender != address(0) && recipient != address(0));
        vm.assume(sender != nftOwner && sender != tl);
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        vm.deal(sender, 2.1 ether);

        uint256 prevSenderBalance = sender.balance;
        uint256 prevNftOwnerBalance = nftOwner.balance;
        uint256 prevTLBalance = tl.balance;

        vm.prank(sender);
        stacks.purchase{value: 1 ether + fee}(address(nft), recipient, 1, 0, emptyProof);
        assert(prevSenderBalance - sender.balance == 1 ether + fee);
        assert(nftOwner.balance - prevNftOwnerBalance == 1 ether);
        assert(tl.balance - prevTLBalance == fee);
        assert(nft.ownerOf(1) == recipient);

        vm.expectRevert(AlreadyReachedMintAllowance.selector);
        vm.prank(sender);
        stacks.purchase{value: 1 ether + fee}(address(nft), recipient, 1, 0, emptyProof);
    }

    /// @dev test purchase for another address erc20
    function test_purchaseForSomeoneElseERC20(address sender, address recipient) public {
        vm.assume(sender != address(0) && recipient != address(0));
        vm.assume(sender != nftOwner && sender != tl);
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(coin),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        vm.deal(sender, 0.1 ether);
        coin.transfer(sender, 1 ether);

        vm.prank(sender);
        coin.approve(address(stacks), 1 ether);

        uint256 prevSenderBalance = sender.balance;
        uint256 prevSenderCoinBalance = coin.balanceOf(sender);
        uint256 prevNftOwnerBalance = coin.balanceOf(nftOwner);
        uint256 prevTLBalance = tl.balance;

        vm.prank(sender);
        stacks.purchase{value: fee}(address(nft), recipient, 1, 0, emptyProof);
        assert(prevSenderBalance - sender.balance == fee);
        assert(prevSenderCoinBalance - coin.balanceOf(sender) == 1 ether);
        assert(coin.balanceOf(nftOwner) - prevNftOwnerBalance == 1 ether);
        assert(tl.balance - prevTLBalance == fee);
        assert(nft.ownerOf(1) == recipient);

        vm.expectRevert(AlreadyReachedMintAllowance.selector);
        vm.prank(sender);
        stacks.purchase{value: fee}(address(nft), recipient, 1, 0, emptyProof);
    }

    /// @dev test numberCanMint
    function test_numberCanMint() public {
        // set drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            3,
            3,
            2,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // test mint one and then get limited to 1 more only
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);
        vm.prank(ben);
        stacks.purchase{value: 2 * fee}(address(nft), ben, 2, 0, emptyProof);
        assert(nft.balanceOf(ben) == 2);

        // test mint two and get limited to remaining supply of 1
        vm.prank(chris);
        stacks.purchase{value: 2 * fee}(address(nft), chris, 2, 0, emptyProof);
        assert(nft.balanceOf(chris) == 1);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
    }

    /// @dev test number minted & reset
    function test_numberMinted(uint256 numberToMint) public {
        // cap fuzz input
        if (numberToMint == 0) {
            numberToMint = 1;
        }
        if (numberToMint > 200) {
            numberToMint = numberToMint % 200 + 1;
        }

        // set drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            numberToMint + 1,
            numberToMint + 1,
            numberToMint,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // mint
        vm.prank(ben);
        stacks.purchase{value: numberToMint * fee}(address(nft), ben, numberToMint, 0, emptyProof);
        assert(stacks.getNumberMinted(address(nft), ben) == numberToMint);

        // close drop and reset
        vm.prank(nftOwner);
        stacks.closeDrop(address(nft));
        assert(stacks.getNumberMinted(address(nft), ben) == 0);
    }

    function _purchaseEth(
        address sender,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] memory proof,
        uint256 cost,
        int256 decayRate,
        bool isPresale
    ) internal {
        vm.startPrank(sender);
        uint256 prevSenderBalance = sender.balance;
        uint256 prevReceiverBalance = receiver.balance;
        uint256 prevTLBalance = tl.balance;
        uint256 prevNftBalance = nft.balanceOf(sender);
        Drop memory prevDrop = stacks.getDrop(address(nft));

        if (prevDrop.publicDuration == 0 && !isPresale) {
            // purchase will fail so exit
            return;
        }

        vm.expectEmit(true, true, true, true);
        emit Purchase(address(nft), sender, address(0), numberToMint, cost, decayRate, isPresale);
        stacks.purchase{value: numberToMint * (cost + fee)}(
            address(nft), sender, numberToMint, presaleNumberCanMint, proof
        );

        Drop memory drop = stacks.getDrop(address(nft));
        uint256 nftBalance = nft.balanceOf(sender);
        assert(prevSenderBalance - sender.balance == numberToMint * (cost + fee));
        assert(receiver.balance - prevReceiverBalance == numberToMint * cost);
        assert(tl.balance - prevTLBalance == numberToMint * fee);
        assert(nftBalance - prevNftBalance == numberToMint);
        assert(prevDrop.supply - drop.supply == numberToMint);
        assert(prevDrop.initialSupply == drop.initialSupply);
        assert(drop.initialSupply != drop.supply);
        if (decayRate != 0 && decayRate < 0 && uint256(-1 * decayRate) * numberToMint > prevDrop.publicDuration) {
            assert(drop.publicDuration == 0);
        } else if (decayRate != 0) {
            assert(int256(drop.publicDuration) - int256(prevDrop.publicDuration) == int256(numberToMint) * decayRate);
        }
        vm.stopPrank();
    }

    /// @dev test purchase functionality for eth, regular mint
    function test_purchaseEthRegular(
        uint256 startDelay,
        uint256 presaleDuration,
        uint256 presaleCost,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        // merkle tree
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1))); // mint only on presale
        data[1] = keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3))); // mint all three on presale (more than public allowance)
        data[2] = keccak256(abi.encode(keccak256(abi.encode(david)), uint256(2))); // mint 1 on presale and 1 on public
        data[3] = keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(2))); // mint 0 on presale and 2 on public
        bytes32 root = m.getRoot(data);

        // limit fuzz variables
        if (startDelay > 365 days) {
            startDelay = startDelay % 365 days;
        }

        if (presaleDuration > 365 days) {
            presaleDuration = presaleDuration % 365 days;
        }

        if (publicDuration > 365 days) {
            publicDuration = publicDuration % 365 days;
        }

        if (presaleCost > 30 ether) {
            presaleCost = presaleCost % 30 ether;
        }

        if (publicCost > 30 ether) {
            publicCost = publicCost % 30 ether;
        }

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            10,
            10,
            2,
            address(0),
            block.timestamp + startDelay,
            presaleDuration,
            presaleCost,
            root,
            publicDuration,
            publicCost,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        bytes32[] memory proof = m.getProof(data, 0);
        uint256 tokensBought = 0;

        // test drop not started
        if (startDelay > 0) {
            // expect revert when trying to mint
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: presaleCost + fee}(address(nft), ben, 1, 1, proof);

            // warp to start time
            vm.warp(drop.startTime);
        }

        // test presale
        if (presaleDuration > 0) {
            // ben buys one token
            _purchaseEth(ben, 1, 1, m.getProof(data, 0), drop.presaleCost, 0, true);

            // chris buys 3 tokens
            _purchaseEth(chris, 3, 3, m.getProof(data, 1), drop.presaleCost, 0, true);

            // david buys 1 token
            _purchaseEth(david, 1, 2, m.getProof(data, 2), drop.presaleCost, 0, true);

            // count tokens bought and warp time
            tokensBought += 5;
            vm.warp(drop.startTime + drop.presaleDuration);
        }

        // test public sale
        if (publicDuration > 0) {
            // ben buys another token
            _purchaseEth(ben, 1, 1, m.getProof(data, 0), drop.publicCost, 0, false);

            // david buys another token
            _purchaseEth(david, 1, 2, m.getProof(data, 2), drop.publicCost, 0, false);

            // bsy buys two tokens
            _purchaseEth(bsy, 2, 2, m.getProof(data, 3), drop.publicCost, 0, false);

            // minter buys one token
            _purchaseEth(minter, 1, 0, emptyProof, drop.publicCost, 0, false);

            // count tokens bought and warp time
            tokensBought += 5;
        }

        // test drop ended (warp to end if hasn't minted out)
        if (tokensBought == drop.supply) {
            // assert drop ended before warping time
            Drop memory rDrop = stacks.getDrop(address(nft));
            assert(rDrop.supply == 0);
            assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
        }
        vm.warp(drop.startTime + drop.presaleDuration + drop.publicDuration);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);

        // test token uris
        for (uint256 i = 0; i < tokensBought; i++) {
            assert(
                keccak256(bytes(nft.tokenURI(i + 1))) == keccak256(abi.encodePacked(drop.baseUri, "/", (i).toString()))
            );
        }
    }

    /// @dev test purchase functionality for eth, velocity mint
    function test_purchaseEthVelocity(uint256 startDelay, uint256 publicDuration, uint256 publicCost, int256 decayRate)
        public
    {
        // limit fuzz variables
        if (startDelay > 365 days) {
            startDelay = startDelay % 365 days;
        }

        if (publicDuration > 365 days) {
            publicDuration = publicDuration % 365 days;
        }

        if (publicCost > 30 ether) {
            publicCost = publicCost % 30 ether;
        }

        if (decayRate > 365 days) {
            decayRate = decayRate % 365 days;
        }

        if (decayRate < -1 * 365 days) {
            decayRate = decayRate % (-1 * 365 days);
        }

        // setup drop
        Drop memory drop = Drop(
            DropType.VELOCITY,
            receiver,
            10,
            10,
            2,
            address(0),
            block.timestamp + startDelay,
            0,
            0,
            bytes32(0),
            publicDuration,
            publicCost,
            decayRate,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // test drop not started
        if (startDelay > 0) {
            // expect revert when trying to mint
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: publicCost + fee}(address(nft), ben, 1, 0, emptyProof);

            // warp to start time
            vm.warp(drop.startTime);
        }

        // test public sale
        if (publicDuration > 0) {
            // ben buys another token
            _purchaseEth(ben, 1, 0, emptyProof, drop.publicCost, decayRate, false);

            // david buys another token
            _purchaseEth(david, 1, 0, emptyProof, drop.publicCost, decayRate, false);

            // bsy buys two tokens
            _purchaseEth(bsy, 2, 0, emptyProof, drop.publicCost, decayRate, false);

            // minter buys one token
            _purchaseEth(minter, 1, 0, emptyProof, drop.publicCost, decayRate, false);
        }

        // test drop ended (warp to end if hasn't minted out)
        Drop memory rDrop = stacks.getDrop(address(nft));
        if (rDrop.publicDuration == 0) {
            assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
        }
        vm.warp(rDrop.startTime + rDrop.presaleDuration + rDrop.publicDuration);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
    }

    function _purchaseERC20(
        address sender,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] memory proof,
        uint256 cost,
        int256 decayRate,
        bool isPresale
    ) internal {
        vm.startPrank(sender);
        uint256 prevSenderBalance = sender.balance;
        // uint256 prevSenderCoinBalance = coin.balanceOf(sender);
        uint256 prevReceiverBalance = coin.balanceOf(receiver);
        uint256 prevTLBalance = tl.balance;
        uint256 prevNftBalance = nft.balanceOf(sender);
        Drop memory prevDrop = stacks.getDrop(address(nft));

        if (prevDrop.publicDuration == 0 && !isPresale) {
            // purchase will fail so exit
            return;
        }

        vm.expectEmit(true, true, true, true);
        emit Purchase(address(nft), sender, address(coin), numberToMint, cost, decayRate, isPresale);
        stacks.purchase{value: numberToMint * fee}(address(nft), sender, numberToMint, presaleNumberCanMint, proof);

        Drop memory drop = stacks.getDrop(address(nft));
        uint256 nftBalance = nft.balanceOf(sender);
        assert(prevSenderBalance - sender.balance == numberToMint * fee);
        // assert(prevSenderCoinBalance - coin.balanceOf(sender) == numberToMint * cost);
        assert(coin.balanceOf(receiver) - prevReceiverBalance == numberToMint * cost);
        assert(tl.balance - prevTLBalance == numberToMint * fee);
        assert(nftBalance - prevNftBalance == numberToMint);
        assert(prevDrop.supply - drop.supply == numberToMint);
        assert(prevDrop.initialSupply == drop.initialSupply);
        assert(drop.initialSupply != drop.supply);
        if (decayRate != 0 && decayRate < 0 && uint256(-1 * decayRate) * numberToMint > prevDrop.publicDuration) {
            assert(drop.publicDuration == 0);
        } else if (decayRate != 0) {
            assert(int256(drop.publicDuration) - int256(prevDrop.publicDuration) == int256(numberToMint) * decayRate);
        }
        vm.stopPrank();
    }

    /// @dev test purchase functionality for erc20, regular mint
    function test_purchaseERC20Regular(
        uint256 startDelay,
        uint256 presaleDuration,
        uint256 presaleCost,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        // merkle tree
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1))); // mint only on presale
        data[1] = keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3))); // mint all three on presale (more than public allowance)
        data[2] = keccak256(abi.encode(keccak256(abi.encode(david)), uint256(2))); // mint 1 on presale and 1 on public
        data[3] = keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(2))); // mint 0 on presale and 2 on public
        bytes32 root = m.getRoot(data);

        // limit fuzz variables
        if (startDelay > 365 days) {
            startDelay = startDelay % 365 days;
        }

        if (presaleDuration > 365 days) {
            presaleDuration = presaleDuration % 365 days;
        }

        if (publicDuration > 365 days) {
            publicDuration = publicDuration % 365 days;
        }

        if (presaleCost > 30 ether) {
            presaleCost = presaleCost % 30 ether;
        }

        if (publicCost > 30 ether) {
            publicCost = publicCost % 30 ether;
        }

        // approve erc20
        vm.prank(ben);
        coin.approve(address(stacks), 100 ether);
        vm.prank(chris);
        coin.approve(address(stacks), 100 ether);
        vm.prank(david);
        coin.approve(address(stacks), 100 ether);
        vm.prank(bsy);
        coin.approve(address(stacks), 100 ether);
        vm.prank(minter);
        coin.approve(address(stacks), 100 ether);

        // setup drop
        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            10,
            10,
            2,
            address(coin),
            block.timestamp + startDelay,
            presaleDuration,
            presaleCost,
            root,
            publicDuration,
            publicCost,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        bytes32[] memory proof = m.getProof(data, 0);
        uint256 tokensBought = 0;

        // test drop not started
        if (startDelay > 0) {
            // expect revert when trying to mint
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: presaleCost + fee}(address(nft), ben, 1, 1, proof);

            // warp to start time
            vm.warp(drop.startTime);
        }

        // test presale
        if (presaleDuration > 0) {
            // ben buys one token
            _purchaseERC20(ben, 1, 1, m.getProof(data, 0), drop.presaleCost, 0, true);

            // chris buys 3 tokens
            _purchaseERC20(chris, 3, 3, m.getProof(data, 1), drop.presaleCost, 0, true);

            // david buys 1 token
            _purchaseERC20(david, 1, 2, m.getProof(data, 2), drop.presaleCost, 0, true);

            // count tokens bought and warp time
            tokensBought += 5;
            vm.warp(drop.startTime + drop.presaleDuration);
        }

        // test public sale
        if (publicDuration > 0) {
            // ben buys another token
            _purchaseERC20(ben, 1, 1, m.getProof(data, 0), drop.publicCost, 0, false);

            // david buys another token
            _purchaseERC20(david, 1, 2, m.getProof(data, 2), drop.publicCost, 0, false);

            // bsy buys two tokens
            _purchaseERC20(bsy, 2, 2, m.getProof(data, 3), drop.publicCost, 0, false);

            // minter buys one token
            _purchaseERC20(minter, 1, 0, emptyProof, drop.publicCost, 0, false);

            // count tokens bought and warp time
            tokensBought += 5;
        }

        // test drop ended (warp to end if hasn't minted out)
        if (tokensBought == drop.supply) {
            // assert drop ended before warping time
            Drop memory rDrop = stacks.getDrop(address(nft));
            assert(rDrop.supply == 0);
            assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
        }
        vm.warp(drop.startTime + drop.presaleDuration + drop.publicDuration);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);

        // test token uris
        for (uint256 i = 0; i < tokensBought; i++) {
            assert(
                keccak256(bytes(nft.tokenURI(i + 1))) == keccak256(abi.encodePacked(drop.baseUri, "/", (i).toString()))
            );
        }
    }

    /// @dev test purchase functionality for erc20, velocity mint
    function test_purchaseERC20Velocity(
        uint256 startDelay,
        uint256 publicDuration,
        uint256 publicCost,
        int256 decayRate
    ) public {
        // limit fuzz variables
        if (startDelay > 365 days) {
            startDelay = startDelay % 365 days;
        }

        if (publicDuration > 365 days) {
            publicDuration = publicDuration % 365 days;
        }

        if (publicCost > 30 ether) {
            publicCost = publicCost % 30 ether;
        }

        if (decayRate > 365 days) {
            decayRate = decayRate % 365 days;
        }

        if (decayRate < -1 * 365 days) {
            decayRate = decayRate % (-1 * 365 days);
        }

        // approve erc20
        vm.prank(ben);
        coin.approve(address(stacks), 100 ether);
        vm.prank(chris);
        coin.approve(address(stacks), 100 ether);
        vm.prank(david);
        coin.approve(address(stacks), 100 ether);
        vm.prank(bsy);
        coin.approve(address(stacks), 100 ether);
        vm.prank(minter);
        coin.approve(address(stacks), 100 ether);

        // setup drop
        Drop memory drop = Drop(
            DropType.VELOCITY,
            receiver,
            10,
            10,
            2,
            address(coin),
            block.timestamp + startDelay,
            0,
            0,
            bytes32(0),
            publicDuration,
            publicCost,
            decayRate,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // test drop not started
        if (startDelay > 0) {
            // expect revert when trying to mint
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: publicCost + fee}(address(nft), ben, 1, 0, emptyProof);

            // warp to start time
            vm.warp(drop.startTime);
        }

        // test public sale
        if (publicDuration > 0) {
            // ben buys another token
            _purchaseERC20(ben, 1, 0, emptyProof, drop.publicCost, decayRate, false);

            // david buys another token
            _purchaseERC20(david, 1, 0, emptyProof, drop.publicCost, decayRate, false);

            // bsy buys two tokens
            _purchaseERC20(bsy, 2, 0, emptyProof, drop.publicCost, decayRate, false);

            // minter buys one token
            _purchaseERC20(minter, 1, 0, emptyProof, drop.publicCost, decayRate, false);
        }

        // test drop ended (warp to end if hasn't minted out)
        Drop memory rDrop = stacks.getDrop(address(nft));
        if (rDrop.publicDuration == 0) {
            assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
        }
        vm.warp(rDrop.startTime + rDrop.presaleDuration + rDrop.publicDuration);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
    }

    /// @dev test purchase two drops simultaneously
    function test_twoSimultaneousDrops() public {
        Drop memory dropOne = Drop(
            DropType.REGULAR,
            receiver,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "htts://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), dropOne);

        Drop memory dropTwo = Drop(
            DropType.REGULAR,
            receiver,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "htts://arweave.net/123"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nftTwo), dropTwo);

        // mint from drop one and assure it doesn't affect drop two
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);
        dropOne = stacks.getDrop(address(nft));
        dropTwo = stacks.getDrop(address(nftTwo));
        assert(dropOne.supply == 9);
        assert(dropTwo.supply == 10);

        // mint from drop two and assure it doesn't affect drop one
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nftTwo), ben, 1, 0, emptyProof);
        dropOne = stacks.getDrop(address(nft));
        dropTwo = stacks.getDrop(address(nftTwo));
        assert(dropOne.supply == 9);
        assert(dropTwo.supply == 9);
    }

    function test_sellOut() public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            1,
            1,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "htts://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // mint from drop one and assure it doesn't affect drop two
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);
        drop = stacks.getDrop(address(nft));
        assert(drop.supply == 0);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);

        vm.expectRevert(YouShallNotMint.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);
    }

    function test_sanctions() public {
        address oracle = makeAddr(unicode"sanctions are the best 🫠");
        stacks.setSanctionsOracle(oracle);

        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));

        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            0,
            0,
            "htts://arweave.net/abc"
        );

        // test configuration function
        vm.prank(nftOwner);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.configureDrop(address(nft), drop);

        // configure drop
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        vm.mockCall(oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(true));

        // can't update payout receiver
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropPayoutReceiver(address(nft), ben);

        // can't buy msg.sender
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);

        // can't buy recipient
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof);

        vm.clearMockedCalls();
    }
}

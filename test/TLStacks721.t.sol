// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {Merkle} from "test/utils/murky/Merkle.sol";
import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {IERC20Errors} from "@openzeppelin-contracts-5.6.1/interfaces/draft-IERC6093.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/utils/PausableUpgradeable.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {IChainalysisSanctionsOracle, SanctionsCompliance} from "src/lib/SanctionsCompliance.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {ITLStacks721Events, Drop} from "src/utils/TLStacks721Utils.sol";
import {DropPhase, DropType, DropErrors} from "src/utils/CommonUtils.sol";
import {Receiver, RevertingReceiver} from "test/utils/Receiver.sol";
import {TransferHelper} from "src/lib/TransferHelper.sol";
import {CurrencyAllowlist} from "src/lib/CurrencyAllowlist.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {BlocklistERC20} from "test/utils/BlocklistERC20.sol";

contract TLStacks721Test is Test, ITLStacks721Events, DropErrors {
    uint256 rid; // drop round to purchase from, fetched ahead of any pranks or expected reverts

    using Strings for uint256;

    uint256 constant BASIS = 10_000;
    bytes32 constant MINTER_ROLE = keccak256("APPROVED_MINT_CONTRACT");
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

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

    struct Balances {
        uint256 senderEthBalance;
        uint256 senderCoinBalance;
        uint256 receiverEthBalance;
        uint256 receiverCoinBalance;
        uint256 tlEthBalance;
        uint256 nftBalance;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    receive() external payable {}

    function setUp() public {
        stacks = new TLStacks721(address(this), address(0), tl, fee, 0, 0);

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(stacks);

        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", nftOwner, 1_000, nftOwner, empty, false, address(0), 0, address(0));
        vm.prank(nftOwner);
        nft.setApprovedMintContracts(mintAddrs, true);

        coin = new MockERC20(address(this));
        stacks.setCurrencyAllowed(address(coin), true);
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
        nftTwo.initialize("Test ERC721 2", "LFG2", nftOwner, 1_000, nftOwner, empty, false, address(0), 0, address(0));
        vm.prank(nftOwner);
        nftTwo.setApprovedMintContracts(mintAddrs, true);
    }

    /// @dev test constructor setup
    function test_setUp() public view {
        assertEq(stacks.owner(), address(this));
        assertEq(stacks.protocolFeeReceiver(), tl);
        assertEq(stacks.protocolFee(), fee);
        assertFalse(stacks.paused());
        assertTrue(nft.hasRole(MINTER_ROLE, address(stacks)));
    }

    /// @dev test constructor
    function test_constructor(
        address initOwner,
        address initSanctionsOracle,
        address initProtocolFeeReceiver,
        uint256 initProtocolFee,
        uint256 initEthSellerFeeBps,
        uint256 initErc20SellerFeeBps
    ) public {
        initEthSellerFeeBps = bound(initEthSellerFeeBps, 0, 500);
        initErc20SellerFeeBps = bound(initErc20SellerFeeBps, 0, 500);
        vm.assume(initOwner != address(0));
        vm.assume(
            initProtocolFeeReceiver != address(0)
                || (initProtocolFee == 0 && initEthSellerFeeBps == 0 && initErc20SellerFeeBps == 0)
        );
        assumeNotPrecompile(initSanctionsOracle);
        assumeNotForgeAddress(initSanctionsOracle);
        vm.mockCall(
            initSanctionsOracle,
            abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector),
            abi.encode(false)
        );

        stacks = new TLStacks721(
            initOwner,
            initSanctionsOracle,
            initProtocolFeeReceiver,
            initProtocolFee,
            initEthSellerFeeBps,
            initErc20SellerFeeBps
        );

        assertEq(stacks.owner(), initOwner);
        assertEq(address(stacks.oracle()), initSanctionsOracle);
        assertEq(stacks.protocolFeeReceiver(), initProtocolFeeReceiver);
        assertEq(stacks.protocolFee(), initProtocolFee);
        assertEq(stacks.ethSellerFeeBps(), initEthSellerFeeBps);
        assertEq(stacks.erc20SellerFeeBps(), initErc20SellerFeeBps);
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
        stacks.setProtocolFeeSettings(sender, 1 ether, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.withdrawFunds(address(0), 100);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, sender));
        stacks.waiveSellerFee(address(nft));
        vm.stopPrank();

        // pass for owner
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(address(this), address(this));
        stacks.transferOwnership(address(this));
        assertEq(stacks.pendingOwner(), address(this));
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), address(this));
        stacks.acceptOwnership();
        assertEq(stacks.pendingOwner(), address(0));
        vm.expectEmit(true, true, false, false);
        emit ProtocolFeeUpdated(address(0), 0, 0, 0);
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(address(0), 1, 0, 0);
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(address(0), 0, 1, 0);
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(address(0), 0, 0, 1);
        stacks.setProtocolFeeSettings(address(0), 0, 0, 0);
        assertEq(stacks.protocolFeeReceiver(), address(0));
        assertEq(stacks.protocolFee(), 0);
        vm.expectEmit(false, false, false, true);
        emit Paused(address(this));
        stacks.pause(true);
        vm.expectEmit(false, false, false, true);
        emit Unpaused(address(this));
        stacks.pause(false);
    }

    /// @dev test withdraw ETH sent to the contract
    function test_withdrawFunds_eth(uint256 amount) public {
        vm.assume(amount > 0);
        if (amount > 100 ether) {
            amount = amount % 100 ether + 1;
        }
        vm.deal(address(stacks), amount);

        uint256 prevBalance = address(this).balance;
        stacks.withdrawFunds(address(0), amount);
        assertEq(address(stacks).balance, 0);
        assertEq(address(this).balance - prevBalance, amount);
    }

    /// @dev test withdraw ERC-20 sent to the contract
    function test_withdrawFunds_erc20(uint256 amount) public {
        vm.assume(amount > 0);
        if (amount > 100 ether) {
            amount = amount % 100 ether + 1;
        }

        vm.prank(bsy);
        coin.transfer(address(stacks), amount);

        uint256 prevBalance = coin.balanceOf(address(this));
        stacks.withdrawFunds(address(coin), amount);
        assertEq(coin.balanceOf(address(stacks)), 0);
        assertEq(coin.balanceOf(address(this)) - prevBalance, amount);
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
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        stacks.updateDropSupply(address(nft), 5);
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
        stacks.updateDropSupply(address(nft), 10);
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
        stacks.updateDropSupply(address(nft), 10);
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
        stacks.updateDropSupply(address(nft), 10);
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
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropSupply(address(nft), 5);
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
        // not configured drop type, which would skip the live drop check and round increment
        drop.decayRate = 0;
        drop.dropType = DropType.NOT_CONFIGURED;
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
        vm.assume(currencyAddress != address(0) && currencyAddress != address(coin));
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

        // currency must be allowlisted
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        stacks.updateDropPrices(address(nft), currencyAddress, presaleCost, publicCost);
        vm.stopPrank();
        stacks.setCurrencyAllowed(currencyAddress, true);

        // any price and allowlisted currency can be set
        drop.currencyAddress = currencyAddress;
        drop.presaleCost = presaleCost;
        drop.publicCost = publicCost;
        vm.startPrank(nftOwner);
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
    function test_updateDropDurationRegular(uint256 startTime, uint256 presaleDuration, uint256 publicDuration) public {
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

    /// @dev test update drop merkle root for velocity mint
    function test_updateDropPresaleMerkleRoot_velocity(bytes32 presaleMerkleRoot) public {
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
            0,
            "https://arweave.net/abc"
        );
        vm.startPrank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        drop.presaleMerkleRoot = presaleMerkleRoot;
        vm.expectRevert(NotAllowedForVelocityDrops.selector);
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
        vm.expectEmit(true, true, true, true);
        emit DropConfigured(address(nft), drop);
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
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1)))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3)))));
        data[2] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(david)), uint256(4)))));
        data[3] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(5)))));
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
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(MintZeroTokens.selector);
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 0, 1, proof, address(0), type(uint256).max, rid);

        // not on allowlist
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(NotOnAllowlist.selector);
        vm.prank(minter);
        stacks.purchase{value: fee + 0.1 ether}(
            address(nft), minter, 1, 1, emptyProof, address(0), type(uint256).max, rid
        );

        // reached mint allowance
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 1, 1, proof, address(0), type(uint256).max, rid);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(ben);
        stacks.purchase{value: fee + 0.1 ether}(address(nft), ben, 1, 1, proof, address(0), type(uint256).max, rid);

        // insufficent funds
        proof = m.getProof(data, 1);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(IncorrectFunds.selector);
        vm.prank(chris);
        stacks.purchase{value: 0.1 ether}(address(nft), chris, 1, 3, proof, address(0), type(uint256).max, rid);

        // too many funds
        proof = m.getProof(data, 1);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(IncorrectFunds.selector);
        vm.prank(chris);
        stacks.purchase{value: 1 ether}(address(nft), chris, 1, 3, proof, address(0), type(uint256).max, rid);
    }

    /// @dev test purchase with erc20 errors
    function test_purchaseERC20Errors() public {
        // merkle tree
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1)))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3)))));
        data[2] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(david)), uint256(4)))));
        data[3] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(5)))));
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
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(MintZeroTokens.selector);
        vm.prank(ben);
        stacks.purchase(address(nft), ben, 0, 1, proof, address(coin), type(uint256).max, rid);

        // not on allowlist
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(NotOnAllowlist.selector);
        vm.prank(minter);
        stacks.purchase(address(nft), minter, 1, 1, emptyProof, address(coin), type(uint256).max, rid);

        // reached mint allowance
        vm.prank(ben);
        coin.approve(address(stacks), 1 ether);
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase(address(nft), ben, 1, 1, proof, address(coin), type(uint256).max, rid);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(ben);
        stacks.purchase(address(nft), ben, 1, 1, proof, address(coin), type(uint256).max, rid);

        // protocol fee isn't charged in eth on erc20 drops
        proof = m.getProof(data, 1);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(IncorrectFunds.selector);
        vm.prank(chris);
        stacks.purchase{value: fee}(address(nft), chris, 1, 3, proof, address(coin), type(uint256).max, rid);

        // too much fee
        proof = m.getProof(data, 1);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(IncorrectFunds.selector);
        vm.prank(chris);
        stacks.purchase{value: 1 ether}(address(nft), chris, 1, 3, proof, address(coin), type(uint256).max, rid);

        // not enough erc20 allowance given
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(stacks), 0, 0.1 ether)
        );
        vm.prank(chris);
        stacks.purchase(address(nft), chris, 1, 3, proof, address(coin), type(uint256).max, rid);

        // not enough erc20 balance
        vm.prank(chris);
        coin.transfer(ben, 100 ether);
        vm.prank(chris);
        coin.approve(address(stacks), 1 ether);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, chris, 0, 0.1 ether));
        vm.prank(chris);
        stacks.purchase(address(nft), chris, 1, 3, proof, address(coin), type(uint256).max, rid);
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

        rid = stacks.getDropRound(address(nft));
        vm.prank(sender);
        stacks.purchase{value: 1 ether + fee}(
            address(nft), recipient, 1, 0, emptyProof, address(0), type(uint256).max, rid
        );
        assert(prevSenderBalance - sender.balance == 1 ether + fee);
        assert(nftOwner.balance - prevNftOwnerBalance == 1 ether);
        assert(tl.balance - prevTLBalance == fee);
        assert(nft.ownerOf(1) == recipient);

        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(sender);
        stacks.purchase{value: 1 ether + fee}(
            address(nft), recipient, 1, 0, emptyProof, address(0), type(uint256).max, rid
        );
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

        rid = stacks.getDropRound(address(nft));
        vm.prank(sender);
        stacks.purchase(address(nft), recipient, 1, 0, emptyProof, address(coin), type(uint256).max, rid);
        assert(prevSenderBalance == sender.balance);
        assert(prevSenderCoinBalance - coin.balanceOf(sender) == 1 ether);
        assert(coin.balanceOf(nftOwner) - prevNftOwnerBalance == 1 ether);
        assert(tl.balance == prevTLBalance);
        assert(nft.ownerOf(1) == recipient);

        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(sender);
        stacks.purchase(address(nft), recipient, 1, 0, emptyProof, address(coin), type(uint256).max, rid);
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
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(ben);
        stacks.purchase{value: 2 * fee}(address(nft), ben, 2, 0, emptyProof, address(0), type(uint256).max, rid);
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        assert(nft.balanceOf(ben) == 2);

        // test mint two and get limited to remaining supply of 1
        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        vm.prank(chris);
        stacks.purchase{value: 2 * fee}(address(nft), chris, 2, 0, emptyProof, address(0), type(uint256).max, rid);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: fee}(address(nft), chris, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        assert(nft.balanceOf(chris) == 1);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
    }

    /// @dev presale mints are capped by the merkle leaf and public mints by the allowance, tracked separately
    function test_presaleAndPublicAllowancesSeparate() public {
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(3)))));
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(1)))));
        bytes32[] memory proof = m.getProof(data, 0);

        Drop memory drop = Drop(
            DropType.REGULAR,
            receiver,
            20,
            20,
            2,
            address(0),
            block.timestamp,
            1000,
            0,
            m.getRoot(data),
            1000,
            0,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);
        rid = stacks.getDropRound(address(nft));

        // ben mints his full presale leaf, which is more than the public allowance
        vm.startPrank(ben);
        stacks.purchase{value: 3 * fee}(address(nft), ben, 3, 3, proof, address(0), type(uint256).max, rid);
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 3, proof, address(0), type(uint256).max, rid);
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(address(nft), ben);
        assertEq(presaleMinted, 3);
        assertEq(publicMinted, 0);

        // presale mints don't use up the public allowance
        vm.warp(drop.startTime + drop.presaleDuration);
        stacks.purchase{value: 2 * fee}(address(nft), ben, 2, 0, emptyProof, address(0), type(uint256).max, rid);
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        vm.stopPrank();
        (presaleMinted, publicMinted) = stacks.getNumberMinted(address(nft), ben);
        assertEq(presaleMinted, 3);
        assertEq(publicMinted, 2);

        // wallets that skipped the presale get the same public allowance
        vm.prank(david);
        stacks.purchase{value: 2 * fee}(address(nft), david, 2, 0, emptyProof, address(0), type(uint256).max, rid);
        (presaleMinted, publicMinted) = stacks.getNumberMinted(address(nft), david);
        assertEq(presaleMinted, 0);
        assertEq(publicMinted, 2);
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
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: numberToMint * fee}(
            address(nft), ben, numberToMint, 0, emptyProof, address(0), type(uint256).max, rid
        );
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(address(nft), ben);
        assertEq(presaleMinted, 0);
        assertEq(publicMinted, numberToMint);

        // close drop and reset
        vm.prank(nftOwner);
        stacks.closeDrop(address(nft));
        (presaleMinted, publicMinted) = stacks.getNumberMinted(address(nft), ben);
        assertEq(presaleMinted, 0);
        assertEq(publicMinted, 0);
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
        Balances memory prevBalances =
            Balances(sender.balance, 0, receiver.balance, 0, tl.balance, nft.balanceOf(sender));
        Drop memory prevDrop = stacks.getDrop(address(nft));

        if (prevDrop.publicDuration == 0 && !isPresale) {
            // purchase will fail so exit
            return;
        }

        rid = stacks.getDropRound(address(nft));
        vm.expectEmit(true, true, true, true);
        emit Purchase(address(nft), sender, address(0), numberToMint, cost, decayRate, isPresale);
        stacks.purchase{value: numberToMint * (cost + fee)}(
            address(nft), sender, numberToMint, presaleNumberCanMint, proof, address(0), type(uint256).max, rid
        );

        Drop memory drop = stacks.getDrop(address(nft));

        assertEq(prevBalances.senderEthBalance - sender.balance, numberToMint * (cost + fee));
        assertEq(receiver.balance - prevBalances.receiverEthBalance, numberToMint * cost);
        assertEq(tl.balance - prevBalances.tlEthBalance, numberToMint * fee);
        assertEq(nft.balanceOf(sender) - prevBalances.nftBalance, numberToMint);
        assertEq(prevDrop.supply - drop.supply, numberToMint);
        assertEq(prevDrop.initialSupply, drop.initialSupply);
        assertNotEq(drop.initialSupply, drop.supply);
        if (decayRate != 0 && decayRate < 0 && uint256(-1 * decayRate) * numberToMint > prevDrop.publicDuration) {
            assertEq(drop.publicDuration, 0);
        } else if (decayRate != 0) {
            assertEq(int256(drop.publicDuration) - int256(prevDrop.publicDuration), int256(numberToMint) * decayRate);
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
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1))))); // mint only on presale
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3))))); // mint all three on presale (more than public allowance)
        data[2] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(david)), uint256(2))))); // mint 1 on presale and 1 on public
        data[3] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(2))))); // mint 0 on presale and 2 on public
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
            rid = stacks.getDropRound(address(nft));
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: presaleCost + fee}(
                address(nft), ben, 1, 1, proof, address(0), type(uint256).max, rid
            );

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
            rid = stacks.getDropRound(address(nft));
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase{value: publicCost + fee}(
                address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid
            );

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
        Balances memory prevBalances = Balances(
            sender.balance,
            coin.balanceOf(sender),
            receiver.balance,
            coin.balanceOf(receiver),
            tl.balance,
            nft.balanceOf(sender)
        );
        Drop memory prevDrop = stacks.getDrop(address(nft));

        if (prevDrop.publicDuration == 0 && !isPresale) {
            // purchase will fail so exit
            return;
        }

        rid = stacks.getDropRound(address(nft));
        vm.expectEmit(true, true, true, true);
        emit Purchase(address(nft), sender, address(coin), numberToMint, cost, decayRate, isPresale);
        stacks.purchase(
            address(nft), sender, numberToMint, presaleNumberCanMint, proof, address(coin), type(uint256).max, rid
        );

        Drop memory drop = stacks.getDrop(address(nft));
        assertEq(prevBalances.senderCoinBalance - coin.balanceOf(sender), numberToMint * cost);
        assertEq(prevBalances.senderEthBalance, sender.balance);
        assertEq(coin.balanceOf(receiver) - prevBalances.receiverCoinBalance, numberToMint * cost);
        assertEq(tl.balance, prevBalances.tlEthBalance);
        assertEq(nft.balanceOf(sender) - prevBalances.nftBalance, numberToMint);
        assertEq(prevDrop.supply - drop.supply, numberToMint);
        assertEq(prevDrop.initialSupply, drop.initialSupply);
        assertNotEq(drop.initialSupply, drop.supply);
        if (decayRate != 0 && decayRate < 0 && uint256(-1 * decayRate) * numberToMint > prevDrop.publicDuration) {
            assertEq(drop.publicDuration, 0);
        } else if (decayRate != 0) {
            assertEq(int256(drop.publicDuration) - int256(prevDrop.publicDuration), int256(numberToMint) * decayRate);
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
        data[0] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(ben)), uint256(1))))); // mint only on presale
        data[1] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(chris)), uint256(3))))); // mint all three on presale (more than public allowance)
        data[2] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(david)), uint256(2))))); // mint 1 on presale and 1 on public
        data[3] = keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(bsy)), uint256(2))))); // mint 0 on presale and 2 on public
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
            rid = stacks.getDropRound(address(nft));
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase(address(nft), ben, 1, 1, proof, address(coin), type(uint256).max, rid);

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
            rid = stacks.getDropRound(address(nft));
            vm.expectRevert(YouShallNotMint.selector);
            vm.prank(ben);
            stacks.purchase(address(nft), ben, 1, 0, emptyProof, address(coin), type(uint256).max, rid);

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
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        dropOne = stacks.getDrop(address(nft));
        dropTwo = stacks.getDrop(address(nftTwo));
        assert(dropOne.supply == 9);
        assert(dropTwo.supply == 10);

        // mint from drop two and assure it doesn't affect drop one
        rid = stacks.getDropRound(address(nftTwo));
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nftTwo), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
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
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
        drop = stacks.getDrop(address(nft));
        assert(drop.supply == 0);
        assert(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);

        rid = stacks.getDropRound(address(nft));
        vm.expectRevert(YouShallNotMint.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);
    }

    function test_setProtocolFeeSettings_sanctionedReceiver() public {
        address oracle = makeAddr("oracle");
        stacks.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );

        // sanctioned receiver is rejected, even with a zero fee
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(ben, 1 ether, 0, 0);
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        stacks.setProtocolFeeSettings(ben, 0, 0, 0);

        // and at deployment
        vm.expectRevert(InvalidProtocolFeeReceiver.selector);
        new TLStacks721(address(this), oracle, ben, 1 ether, 0, 0);

        // unsanctioned receiver is fine
        stacks.setProtocolFeeSettings(chris, 1 ether, 0, 0);
        assertEq(stacks.protocolFeeReceiver(), chris);
        vm.clearMockedCalls();
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
        rid = stacks.getDropRound(address(nft));
        vm.prank(ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);

        // can't buy recipient (only the recipient is sanctioned, so the sender check passes)
        rid = stacks.getDropRound(address(nft));
        vm.clearMockedCalls();
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.purchase{value: fee}(address(nft), ben, 1, 0, emptyProof, address(0), type(uint256).max, rid);

        // sanctioned payout receiver can't be set
        vm.clearMockedCalls();
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, ben), abi.encode(true)
        );
        vm.startPrank(nftOwner);
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.updateDropPayoutReceiver(address(nft), ben);
        drop.payoutReceiver = ben;
        vm.expectRevert(InvalidPayoutReceiver.selector);
        stacks.configureDrop(address(nft), drop);
        vm.stopPrank();

        // sanctioned drop admin can't update the drop, but can still close it
        vm.clearMockedCalls();
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, nftOwner),
            abi.encode(true)
        );
        vm.startPrank(nftOwner);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropPayoutReceiver(address(nft), ben);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropAllowance(address(nft), 5);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropPrices(address(nft), address(0), 0, 1);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, 2000);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropPresaleMerkleRoot(address(nft), bytes32(uint256(1)));
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropDecayRate(address(nft), 1);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.updateDropSupply(address(nft), 5);
        stacks.closeDrop(address(nft));
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    // SECURITY HARDENING
    /////////////////////////////////////////////////////////////////////

    /// @dev test that buyers are protected from drop changes made between signing and execution
    function test_purchase_frontRunProtection() public {
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

        // buyer has a large outstanding approval
        vm.prank(chris);
        coin.approve(address(stacks), type(uint256).max);
        vm.deal(chris, 1 ether);
        uint256 prevChrisBalance = coin.balanceOf(chris);

        // admin raises the price in place
        vm.prank(nftOwner);
        stacks.updateDropPrices(address(nft), address(coin), 0, 100 ether);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        vm.expectRevert(PriceTooHigh.selector);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);

        // admin switches the currency in place
        vm.prank(nftOwner);
        stacks.updateDropPrices(address(nft), address(0), 0, 1 ether);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        vm.expectRevert(CurrencyMismatch.selector);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);

        // admin closes and reconfigures the drop at a higher price
        drop.publicCost = 100 ether;
        vm.startPrank(nftOwner);
        stacks.closeDrop(address(nft));
        stacks.configureDrop(address(nft), drop);
        rid = stacks.getDropRound(address(nft));
        vm.stopPrank();
        vm.prank(chris);
        vm.expectRevert(PriceTooHigh.selector);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);

        assertEq(coin.balanceOf(chris), prevChrisBalance);

        // admin closes and reconfigures the drop with new art at the same price while a purchase is pending
        uint256 oldRound = stacks.getDropRound(address(nft));
        drop.publicCost = 1 ether;
        drop.baseUri = "https://arweave.net/xyz";
        vm.startPrank(nftOwner);
        stacks.closeDrop(address(nft));
        stacks.configureDrop(address(nft), drop);
        vm.stopPrank();
        vm.prank(chris);
        vm.expectRevert(DropRoundChanged.selector);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(coin), 1 ether, oldRound);
        assertEq(coin.balanceOf(chris), prevChrisBalance);

        // purchase against the current round succeeds
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);
        assertEq(coin.balanceOf(chris), prevChrisBalance - 1 ether);
    }

    /// @dev test that shortening the presale can't force a pending presale mint to pay the public price
    function test_purchase_presaleShortenedFrontRun() public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(0),
            block.timestamp,
            1000,
            0.1 ether,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // admin ends the presale early, moving the drop into the more expensive public phase
        vm.prank(nftOwner);
        stacks.updateDropDuration(address(nft), block.timestamp, 0, 1000);

        rid = stacks.getDropRound(address(nft));
        vm.deal(chris, 2 ether);
        vm.prank(chris);
        vm.expectRevert(PriceTooHigh.selector);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 0.1 ether, rid);
    }

    /// @dev test that eth payouts revert instead of falling back to weth
    function test_purchase_revertingEthReceiver() public {
        address reverting = address(new RevertingReceiver());
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
        drop.payoutReceiver = reverting;
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        rid = stacks.getDropRound(address(nft));
        vm.deal(chris, 2 ether);
        vm.prank(chris);
        vm.expectRevert(TransferHelper.ETHTransferFailed.selector);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 1 ether, rid);

        // reverting protocol fee receiver
        vm.prank(nftOwner);
        stacks.updateDropPayoutReceiver(address(nft), nftOwner);
        stacks.setProtocolFeeSettings(reverting, fee, 0, 0);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        vm.expectRevert(TransferHelper.ETHTransferFailed.selector);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 1 ether, rid);
    }

    /// @dev test the currency allowlist
    function test_currencyAllowlist() public {
        MockERC20 other = new MockERC20(address(this));
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            1,
            address(other),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            1 ether,
            0,
            "https://arweave.net/abc"
        );

        // owner only
        vm.prank(chris);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, chris));
        stacks.setCurrencyAllowed(address(other), true);

        // non-allowlisted currency can't be configured
        vm.prank(nftOwner);
        vm.expectRevert(CurrencyAllowlist.CurrencyNotAllowed.selector);
        stacks.configureDrop(address(nft), drop);

        // allowlisting enables the drop
        vm.expectEmit(true, true, true, true);
        emit CurrencyAllowlist.CurrencyAllowlistUpdated(address(other), true);
        stacks.setCurrencyAllowed(address(other), true);
        assertTrue(stacks.allowedCurrencies(address(other)));
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        // removing a currency doesn't affect live drops
        stacks.setCurrencyAllowed(address(other), false);
        other.transfer(chris, 10 ether);
        vm.deal(chris, 1 ether);
        vm.startPrank(chris);
        other.approve(address(stacks), 1 ether);
        rid = stacks.getDropRound(address(nft));
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(other), 1 ether, rid);
        vm.stopPrank();
        assertEq(other.balanceOf(nftOwner), 1 ether);

        // eth is always allowed, even if explicitly removed
        stacks.setCurrencyAllowed(address(0), false);
        drop.currencyAddress = address(0);
        vm.startPrank(nftOwner);
        stacks.closeDrop(address(nft));
        stacks.configureDrop(address(nft), drop);
        vm.stopPrank();
    }

    /// @dev test that purchases revert if the payout receiver was sanctioned after the drop was configured
    function test_purchase_sanctionedPayoutReceiver() public {
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

        address oracle = makeAddr("oracle");
        stacks.setSanctionsOracle(oracle);
        vm.mockCall(
            oracle, abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector), abi.encode(false)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IChainalysisSanctionsOracle.isSanctioned.selector, nftOwner),
            abi.encode(true)
        );

        rid = stacks.getDropRound(address(nft));
        vm.deal(chris, 2 ether);
        vm.prank(chris);
        vm.expectRevert(SanctionsCompliance.SanctionedAddress.selector);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 1 ether, rid);
        vm.clearMockedCalls();
    }

    /////////////////////////////////////////////////////////////////////
    // SELLER FEES
    /////////////////////////////////////////////////////////////////////

    /// @dev test setting the seller fees
    function test_setProtocolFeeSettings_sellerFees(uint256 ethBps, uint256 erc20Bps) public {
        ethBps = bound(ethBps, 0, stacks.MAX_SELLER_FEE_BPS());
        erc20Bps = bound(erc20Bps, 0, stacks.MAX_SELLER_FEE_BPS());

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(chris, fee, ethBps, erc20Bps);
        stacks.setProtocolFeeSettings(chris, fee, ethBps, erc20Bps);
        assertEq(stacks.protocolFeeReceiver(), chris);
        assertEq(stacks.protocolFee(), fee);
        assertEq(stacks.ethSellerFeeBps(), ethBps);
        assertEq(stacks.erc20SellerFeeBps(), erc20Bps);

        // seller fees are capped
        vm.expectRevert(InvalidSellerFeeBps.selector);
        stacks.setProtocolFeeSettings(chris, fee, 501, erc20Bps);
        vm.expectRevert(InvalidSellerFeeBps.selector);
        stacks.setProtocolFeeSettings(chris, fee, ethBps, 501);
        vm.expectRevert(InvalidSellerFeeBps.selector);
        new TLStacks721(address(this), address(0), tl, fee, 501, 0);
    }

    /// @dev test the seller fee on eth drops, on top of the flat protocol fee
    function test_purchase_sellerFeeEth(uint256 cost, uint256 numberToMint, uint256 bps) public {
        cost = bound(cost, 0, 10 ether);
        numberToMint = bound(numberToMint, 1, 10);
        bps = bound(bps, 0, 500);
        stacks.setProtocolFeeSettings(tl, fee, bps, 0);

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
            address(0),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            cost,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        uint256 totalSale = numberToMint * cost;
        uint256 sellerFee = totalSale * bps / BASIS;
        vm.deal(chris, totalSale + numberToMint * fee);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: totalSale + numberToMint * fee}(
            address(nft), chris, numberToMint, 0, emptyProof, address(0), cost, rid
        );

        assertEq(chris.balance, 0);
        assertEq(nftOwner.balance, totalSale - sellerFee);
        assertEq(tl.balance, numberToMint * fee + sellerFee);
        assertEq(address(stacks).balance, 0);
    }

    /// @dev test the seller fee on erc20 drops, with no protocol fee charged in eth
    function test_purchase_sellerFeeERC20(uint256 cost, uint256 numberToMint, uint256 bps) public {
        cost = bound(cost, 0, 10 ether);
        numberToMint = bound(numberToMint, 1, 10);
        bps = bound(bps, 0, 500);
        stacks.setProtocolFeeSettings(tl, fee, 0, bps);

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
            address(coin),
            block.timestamp,
            0,
            0,
            bytes32(0),
            1000,
            cost,
            0,
            "https://arweave.net/abc"
        );
        vm.prank(nftOwner);
        stacks.configureDrop(address(nft), drop);

        uint256 totalSale = numberToMint * cost;
        uint256 sellerFee = totalSale * bps / BASIS;
        vm.startPrank(chris);
        coin.approve(address(stacks), totalSale);
        rid = stacks.getDropRound(address(nft));
        stacks.purchase(address(nft), chris, numberToMint, 0, emptyProof, address(coin), cost, rid);
        vm.stopPrank();

        assertEq(coin.balanceOf(chris), 100 ether - totalSale);
        assertEq(chris.balance, 100 ether);
        assertEq(coin.balanceOf(nftOwner), totalSale - sellerFee);
        assertEq(coin.balanceOf(tl), sellerFee);
        assertEq(tl.balance, 0);
        assertEq(coin.balanceOf(address(stacks)), 0);
    }

    /// @dev test waiving the seller fee for a drop round
    function test_waiveSellerFee() public {
        stacks.setProtocolFeeSettings(tl, fee, 500, 500);

        // waive before the drop is configured
        assertFalse(stacks.isSellerFeeWaived(address(nft)));
        vm.expectEmit(true, true, true, true);
        emit SellerFeeWaived(address(nft), 0);
        stacks.waiveSellerFee(address(nft));
        assertTrue(stacks.isSellerFeeWaived(address(nft)));
        assertFalse(stacks.isSellerFeeWaived(address(nftTwo)));

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
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

        // no seller fee while waived
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 1 ether, rid);
        assertEq(nftOwner.balance, 1 ether);
        assertEq(tl.balance, fee);

        // closing the drop starts a new round, which resets the waiver
        vm.startPrank(nftOwner);
        stacks.closeDrop(address(nft));
        stacks.configureDrop(address(nft), drop);
        vm.stopPrank();
        assertFalse(stacks.isSellerFeeWaived(address(nft)));
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: 1 ether + fee}(address(nft), chris, 1, 0, emptyProof, address(0), 1 ether, rid);
        assertEq(nftOwner.balance, 1.95 ether);
        assertEq(tl.balance, 2 * fee + 0.05 ether);

        // waive a live erc20 drop
        drop.currencyAddress = address(coin);
        vm.prank(nftOwner);
        stacks.configureDrop(address(nftTwo), drop);
        stacks.waiveSellerFee(address(nftTwo));
        vm.startPrank(chris);
        coin.approve(address(stacks), 2 ether);
        rid = stacks.getDropRound(address(nftTwo));
        stacks.purchase(address(nftTwo), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);
        vm.stopPrank();
        assertEq(coin.balanceOf(nftOwner), 1 ether);
        assertEq(coin.balanceOf(tl), 0);

        // reconfiguring after the drop ends starts a new round, which resets the waiver
        vm.warp(block.timestamp + 1000);
        drop.startTime = block.timestamp;
        vm.prank(nftOwner);
        stacks.configureDrop(address(nftTwo), drop);
        assertFalse(stacks.isSellerFeeWaived(address(nftTwo)));
        rid = stacks.getDropRound(address(nftTwo));
        vm.prank(chris);
        stacks.purchase(address(nftTwo), chris, 1, 0, emptyProof, address(coin), 1 ether, rid);
        assertEq(coin.balanceOf(nftOwner), 1.95 ether);
        assertEq(coin.balanceOf(tl), 0.05 ether);
    }

    /// @dev test that a blocklisted protocol fee receiver blocks erc20 purchases until the owner rotates it
    function test_purchase_sellerFeeBlocklistedReceiver() public {
        BlocklistERC20 blockCoin = new BlocklistERC20(address(this));
        stacks.setCurrencyAllowed(address(blockCoin), true);
        stacks.setProtocolFeeSettings(tl, fee, 0, 500);
        blockCoin.transfer(chris, 10 ether);
        blockCoin.setBlocked(tl, true);

        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
            address(blockCoin),
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

        vm.prank(chris);
        blockCoin.approve(address(stacks), 1 ether);
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        vm.expectRevert("blocked");
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(blockCoin), 1 ether, rid);

        // rotating the receiver unblocks purchases
        stacks.setProtocolFeeSettings(david, fee, 0, 500);
        vm.prank(chris);
        stacks.purchase(address(nft), chris, 1, 0, emptyProof, address(blockCoin), 1 ether, rid);
        assertEq(blockCoin.balanceOf(nftOwner), 0.95 ether);
        assertEq(blockCoin.balanceOf(david), 0.05 ether);
    }

    /////////////////////////////////////////////////////////////////////
    // SUPPLY
    /////////////////////////////////////////////////////////////////////

    /// @dev test decreasing the drop supply
    function test_updateDropSupply() public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
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

        // mint 3
        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: 3 * fee}(address(nft), chris, 3, 0, emptyProof, address(0), 0, rid);

        // can't increase supply or decrease below the number minted
        vm.startPrank(nftOwner);
        vm.expectRevert(InvalidDropSupply.selector);
        stacks.updateDropSupply(address(nft), 11);
        vm.expectRevert(InvalidDropSupply.selector);
        stacks.updateDropSupply(address(nft), 2);

        // decrease the total supply
        drop.initialSupply = 8;
        drop.supply = 5;
        vm.expectEmit(true, true, true, true);
        emit DropUpdated(address(nft), drop);
        stacks.updateDropSupply(address(nft), 8);
        vm.stopPrank();
        Drop memory rDrop = stacks.getDrop(address(nft));
        assertEq(rDrop.initialSupply, 8);
        assertEq(rDrop.supply, 5);

        // can't mint past the new supply
        vm.prank(chris);
        vm.expectRevert(CannotMintMoreThanAllowed.selector);
        stacks.purchase{value: 6 * fee}(address(nft), chris, 6, 0, emptyProof, address(0), 0, rid);

        // a purchase landing before the update doesn't change the new total
        vm.prank(david);
        stacks.purchase{value: 2 * fee}(address(nft), david, 2, 0, emptyProof, address(0), 0, rid);
        vm.prank(nftOwner);
        stacks.updateDropSupply(address(nft), 6);
        rDrop = stacks.getDrop(address(nft));
        assertEq(rDrop.initialSupply, 6);
        assertEq(rDrop.supply, 1);

        // decreasing to the number minted ends the drop
        vm.prank(nftOwner);
        stacks.updateDropSupply(address(nft), 5);
        rDrop = stacks.getDrop(address(nft));
        assertEq(rDrop.initialSupply, 5);
        assertEq(rDrop.supply, 0);
        assertTrue(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
        vm.prank(nftOwner);
        vm.expectRevert(DropUpdateNotAllowed.selector);
        stacks.updateDropSupply(address(nft), 5);
        assertEq(nft.balanceOf(chris) + nft.balanceOf(david), 5);
    }

    /// @dev fuzz decreasing the drop supply
    function test_updateDropSupply_fuzz(uint256 numberMinted, uint256 newInitialSupply) public {
        numberMinted = bound(numberMinted, 0, 9);
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
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
        if (numberMinted > 0) {
            rid = stacks.getDropRound(address(nft));
            vm.prank(chris);
            stacks.purchase{value: numberMinted * fee}(
                address(nft), chris, numberMinted, 0, emptyProof, address(0), 0, rid
            );
        }

        vm.prank(nftOwner);
        if (newInitialSupply > 10 || newInitialSupply < numberMinted) {
            vm.expectRevert(InvalidDropSupply.selector);
            stacks.updateDropSupply(address(nft), newInitialSupply);
        } else {
            stacks.updateDropSupply(address(nft), newInitialSupply);
            Drop memory rDrop = stacks.getDrop(address(nft));
            assertEq(rDrop.initialSupply, newInitialSupply);
            assertEq(rDrop.supply, newInitialSupply - numberMinted);
            assertEq(rDrop.initialSupply - rDrop.supply, numberMinted);
        }
    }

    /// @dev test that token uris continue in order after the supply is decreased
    function test_updateDropSupply_tokenUris() public {
        Drop memory drop = Drop(
            DropType.REGULAR,
            nftOwner,
            10,
            10,
            10,
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

        rid = stacks.getDropRound(address(nft));
        vm.prank(chris);
        stacks.purchase{value: 3 * fee}(address(nft), chris, 3, 0, emptyProof, address(0), 0, rid);

        vm.prank(nftOwner);
        stacks.updateDropSupply(address(nft), 5);

        vm.prank(david);
        stacks.purchase{value: 2 * fee}(address(nft), david, 2, 0, emptyProof, address(0), 0, rid);

        for (uint256 i = 1; i <= 5; i++) {
            assertEq(nft.tokenURI(i), string(abi.encodePacked("https://arweave.net/abc/", (i - 1).toString())));
        }
        assertTrue(stacks.getDropPhase(address(nft)) == DropPhase.ENDED);
    }
}

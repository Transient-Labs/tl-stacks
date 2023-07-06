// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";
import {Merkle} from "murky/Merkle.sol";

import {ITLStacks721Events, ITLStacks721, Drop} from "tl-stacks/utils/ITLStacks721.sol";
import {DropPhase, DropParam} from "tl-stacks/utils/DropUtils.sol";

import {TLCreator} from "tl-creator-contracts/TLCreator.sol";
import {ERC721TL} from "tl-creator-contracts/core/ERC721TL.sol";
import {NotSpecifiedRole} from "tl-sol-tools/upgradeable/access/OwnableAccessControlUpgradeable.sol";

import {Receiver} from "./utils/Receiver.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract TLStacks721Test is Test, ITLStacks721Events {
    bytes32 constant MINTER_ROLE = keccak256("APPROVED_MINT_CONTRACT");
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    VyperDeployer vyperDeployer = new VyperDeployer();

    ITLStacks721 stacks;
    ERC721TL nft;
    ERC721TL nftTwo;
    MockERC20 coin;

    bytes32[] emptyProof = new bytes32[](0);

    address nftOwner = address(0xABC);
    address receiver;

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);
    address bsy = address(0xCDB);
    address minter = address(0x12345);

    function setUp() public {
        stacks = ITLStacks721(vyperDeployer.deployContract("TLStacks721", abi.encode(address(this))));

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(stacks);

        ERC721TL implementation = new ERC721TL(true);
        TLCreator proxy = new TLCreator(
            address(implementation),
            "Test ERC721",
            "LFG",
            nftOwner,
            1_000,
            nftOwner,
            empty,
            false,
            address(0)
        );
        nft = ERC721TL(address(proxy));
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

        TLCreator proxyTwo = new TLCreator(
            address(implementation),
            "Test ERC721 2",
            "LFG2",
            nftOwner,
            1_000,
            nftOwner,
            empty,
            false,
            address(0)
        );
        nftTwo = ERC721TL(address(proxyTwo));
        vm.prank(nftOwner);
        nftTwo.setApprovedMintContracts(mintAddrs, true);
    }

    /// @dev test constructor setup
    function test_setUp() public {
        assert(stacks.owner() == address(this));
        assertFalse(stacks.paused());
        assertTrue(nft.hasRole(MINTER_ROLE, address(stacks)));
    }

    /// @dev test owner only access for owner functions
    /// @dev reverts if not the owner
    function test_owner_only_access(address sender) public {
        vm.assume(sender != address(this));
        vm.startPrank(sender);
        vm.expectRevert("caller not owner");
        stacks.set_paused(true);
        vm.expectRevert("caller not owner");
        stacks.set_paused(false);
        vm.expectRevert("caller not owner");
        stacks.transfer_ownership(sender);
        vm.stopPrank();
    }

    /// @dev check ownership transfer
    /// @dev should emit an event log for ownership transferred
    /// @dev new owner is reflected in state
    /// @dev reverts when old owner tries to do something
    function test_transfer_ownership(address newOwner) public {
        vm.assume(newOwner != address(this));
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);
        stacks.transfer_ownership(newOwner);
        assert(stacks.owner() == newOwner);
        vm.expectRevert("caller not owner");
        stacks.set_paused(true);
    }

    /// @dev verifies that drop admins or contract owner can access drop write functions
    /// @dev reverts when `notDropAdmin` calls the functions
    function test_drop_admin_access(address dropAdmin, address notDropAdmin) public {
        vm.assume(dropAdmin != nftOwner);
        vm.assume(notDropAdmin != nftOwner);
        vm.assume(dropAdmin != notDropAdmin);

        // test contract owner
        vm.startPrank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            10
        );
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
        stacks.close_drop(address(nft));
        address[] memory admins = new address[](1);
        admins[0] = dropAdmin;
        nft.setRole(ADMIN_ROLE, admins, true);
        vm.stopPrank();

        // test contract admin
        vm.startPrank(dropAdmin);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            10
        );
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
        stacks.close_drop(address(nft));
        nft.renounceRole(ADMIN_ROLE);
        vm.stopPrank();

        // test not admin or contract owner
        vm.startPrank(notDropAdmin);
        vm.expectRevert("not authorized");
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            10
        );
        vm.expectRevert("not authorized");
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
        vm.expectRevert("not authorized");
        stacks.close_drop(address(nft));
        vm.stopPrank();
    }

    /// @dev checks that pausing blocks all necessary functions
    /// @dev pauses regardless of function caller
    function test_paused(address caller) public {
        stacks.set_paused(true);

        vm.startPrank(caller);
        vm.expectRevert("contract is paused");
        stacks.configure_drop(address(1), "baseuri", 100, 1, address(0), address(1), 100, 0, 0, bytes32(0), 100, 0);
        vm.expectRevert("contract is paused");
        stacks.close_drop(address(1));
        vm.expectRevert("contract is paused");
        stacks.update_drop_param(address(1), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(100)));
        vm.expectRevert("contract is paused");
        bytes32[] memory proof = new bytes32[](0);
        stacks.mint(address(1), 1, address(2), proof, 1);

        vm.stopPrank();

        stacks.set_paused(false);
    }

    /// @dev tests `configure_drop` with eth
    /// @dev checks reverting cases as well
    /// @dev checks emitted event
    function test_configure_drop_eth(
        string memory baseUri,
        uint256 supply,
        uint256 allowance,
        address payoutReceiver,
        uint256 startTime,
        uint256 presaleDuration,
        uint256 presaleCost,
        bytes32 presaleMerkleRoot,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        vm.startPrank(nftOwner);

        bool doesNotRevert = false;

        if (startTime == 0) {
            vm.expectRevert("start time cannot be zero");
        } else {
            doesNotRevert = true;
            vm.expectEmit(true, true, true, false);
            emit DropConfigured(nftOwner, address(nft), block.number);
        }

        stacks.configure_drop(
            address(nft),
            baseUri,
            supply,
            allowance,
            address(0),
            payoutReceiver,
            startTime,
            presaleDuration,
            presaleCost,
            presaleMerkleRoot,
            publicDuration,
            publicCost
        );

        if (doesNotRevert) {
            Drop memory drop = stacks.get_drop(address(nft));
            assertEq(drop.base_uri, baseUri);
            assertEq(drop.initial_supply, supply);
            assertEq(drop.supply, supply);
            assertEq(drop.allowance, allowance);
            assertEq(drop.currency_addr, address(0));
            assertEq(drop.payout_receiver, payoutReceiver);
            assertEq(drop.start_time, startTime);
            assertEq(drop.presale_duration, presaleDuration);
            assertEq(drop.presale_cost, presaleCost);
            assertEq(drop.presale_merkle_root, presaleMerkleRoot);
            assertEq(drop.public_duration, publicDuration);
            assertEq(drop.public_cost, publicCost);
        }

        vm.stopPrank();
    }

    /// @dev tests `configure_drop` with erc20
    /// @dev checks reverting cases as well
    /// @dev checks emitted event
    function test_configure_drop_erc20(
        string memory baseUri,
        uint256 supply,
        uint256 allowance,
        address payoutReceiver,
        uint256 startTime,
        uint256 presaleDuration,
        uint256 presaleCost,
        bytes32 presaleMerkleRoot,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        vm.startPrank(nftOwner);

        bool doesNotRevert = false;

        if (startTime == 0) {
            vm.expectRevert("start time cannot be zero");
        } else {
            doesNotRevert = true;
            vm.expectEmit(true, true, true, false);
            emit DropConfigured(nftOwner, address(nft), block.number);
        }

        stacks.configure_drop(
            address(nft),
            baseUri,
            supply,
            allowance,
            address(coin),
            payoutReceiver,
            startTime,
            presaleDuration,
            presaleCost,
            presaleMerkleRoot,
            publicDuration,
            publicCost
        );

        if (doesNotRevert) {
            Drop memory drop = stacks.get_drop(address(nft));
            assertEq(drop.base_uri, baseUri);
            assertEq(drop.initial_supply, supply);
            assertEq(drop.supply, supply);
            assertEq(drop.allowance, allowance);
            assertEq(drop.currency_addr, address(coin));
            assertEq(drop.payout_receiver, payoutReceiver);
            assertEq(drop.start_time, startTime);
            assertEq(drop.presale_duration, presaleDuration);
            assertEq(drop.presale_cost, presaleCost);
            assertEq(drop.presale_merkle_root, presaleMerkleRoot);
            assertEq(drop.public_duration, publicDuration);
            assertEq(drop.public_cost, publicCost);
        }

        vm.stopPrank();
    }

    /// @dev tests `close_drop`
    /// @dev verifies proper event is emitted
    /// @dev verifies reset Drop
    /// @dev verifies drop round increased
    function test_close_drop() public {
        vm.startPrank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0
        );
        uint256 prevRound = stacks.get_drop_round(address(nft));

        vm.expectEmit(true, true, false, false);
        emit DropClosed(nftOwner, address(nft));
        stacks.close_drop(address(nft));

        uint256 currRound = stacks.get_drop_round(address(nft));

        assertEq(currRound, prevRound + 1);

        vm.stopPrank();
    }

    /// @dev tests `update_drop_param`
    /// @dev verifies event emittance
    /// @dev verifies reverting cases
    function test_update_drop_param(bytes32 paramValue) public {
        vm.startPrank(nftOwner);

        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0
        );

        // merkle root
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PRESALE, DropParam.MERKLE_ROOT, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PRESALE, DropParam.MERKLE_ROOT, paramValue);
        // presale cost
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PRESALE, DropParam.COST, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PRESALE, DropParam.COST, paramValue);
        // presale duration
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PRESALE, DropParam.DURATION, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PRESALE, DropParam.DURATION, paramValue);
        // public allowance
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.ALLOWANCE, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.ALLOWANCE, paramValue);
        // public cost
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.COST, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.COST, paramValue);
        // public duration
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, paramValue);
        // start time
        vm.expectEmit(true, true, false, true);
        emit DropUpdated(nftOwner, address(nft), DropPhase.BEFORE_SALE, DropParam.START_TIME, paramValue);
        stacks.update_drop_param(address(nft), DropPhase.BEFORE_SALE, DropParam.START_TIME, paramValue);

        // expect revert
        vm.expectRevert("unknown param update");
        stacks.update_drop_param(address(nft), DropPhase.PRESALE, DropParam.START_TIME, paramValue);
        vm.expectRevert("unknown param update");
        stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.MERKLE_ROOT, paramValue);
        vm.expectRevert("unknown param update");
        stacks.update_drop_param(address(nft), DropPhase.BEFORE_SALE, DropParam.COST, paramValue);
        vm.expectRevert("unknown param update");
        stacks.update_drop_param(address(nft), DropPhase.NOT_CONFIGURED, DropParam.COST, paramValue);

        // check updated params
        Drop memory drop = stacks.get_drop(address(nft));
        assertEq(drop.allowance, uint256(paramValue));
        assertEq(drop.start_time, uint256(paramValue));
        assertEq(drop.presale_duration, uint256(paramValue));
        assertEq(drop.presale_cost, uint256(paramValue));
        assertEq(drop.presale_merkle_root, paramValue);
        assertEq(drop.public_duration, uint256(paramValue));
        assertEq(drop.public_cost, uint256(paramValue));

        vm.stopPrank();
    }

    /// @dev test mint zero tokens
    function test_mint_zero_tokens() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0
        );

        vm.expectRevert("cannot mint zero tokens");
        stacks.mint(address(nft), 0, address(this), emptyProof, 0);
    }

    /// @dev test mint not approved mint contract
    function test_mint_not_approved_mint_contract() public {
        vm.startPrank(nftOwner);
        address[] memory addys = new address[](1);
        addys[0] = address(stacks);
        nft.setRole(MINTER_ROLE, addys, false);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0
        );
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(NotSpecifiedRole.selector, MINTER_ROLE));
        stacks.mint(address(nft), 1, address(this), emptyProof, 0);

        vm.prank(nftOwner);
        nft.setRole(MINTER_ROLE, addys, true);
    }

    /// @dev test supply == 0
    function test_mint_zero_supply() public {
        vm.expectRevert("no supply left");
        stacks.mint(address(nft), 1, address(this), emptyProof, 0);
    }

    /// @dev test not on the allowlist
    function test_not_on_allowlist() public {
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(ben, uint256(1)));
        data[1] = keccak256(abi.encode(chris, uint256(3)));
        data[2] = keccak256(abi.encode(david, uint256(4)));
        data[3] = keccak256(abi.encode(bsy, uint256(5)));
        bytes32 root = m.getRoot(data);

        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            3600,
            0,
            root,
            3600,
            0
        );

        vm.prank(minter);
        vm.expectRevert("not part of allowlist");
        stacks.mint(address(nft), 1, minter, emptyProof, 1);
    }

    /// @dev not enough eth sent
    function test_not_enough_eth_sent() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            1 ether
        );

        vm.prank(ben);
        vm.expectRevert("insufficient funds");
        stacks.mint{value: 0.1 ether}(address(nft), 1, ben, emptyProof, 0);
    }

    /// @dev test not enough erc20 allowance given
    function test_not_enough_allowance_given() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(coin),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            1 ether
        );

        vm.startPrank(ben);
        coin.approve(address(stacks), 0.1 ether);
        vm.expectRevert("insufficient funds");
        stacks.mint(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();
    }

    /// @dev test not enough erc20 balance
    function test_not_enough_balance() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            1,
            address(coin),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            101 ether
        );

        vm.startPrank(ben);
        coin.approve(address(stacks), 1000 ether);
        vm.expectRevert("insufficient funds");
        stacks.mint(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();
    }

    /// @dev mint more than allowance and get limited to allowance
    function test_mint_allowance() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            4,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        uint256 prevBalance = ben.balance;
        stacks.mint{value: 0.005 ether}(address(nft), 5, ben, emptyProof, 0);
        assert(prevBalance - ben.balance == 0.004 ether);
        assert(nft.balanceOf(ben) == 4);
        vm.expectRevert("already hit mint allowance");
        stacks.mint(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();
    }

    /// @dev mint more than supply left and get limited to supply left
    function test_mint_more_than_supply() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            4,
            5,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        uint256 prevBalance = ben.balance;
        stacks.mint{value: 0.005 ether}(address(nft), 5, ben, emptyProof, 0);
        assert(prevBalance - ben.balance == 0.004 ether);
        assert(nft.balanceOf(ben) == 4);
        vm.expectRevert("no supply left");
        stacks.mint(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();
    }

    /// @dev test send more eth than needed and get refunded extra eth
    function test_mint_too_much_eth() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            5,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        uint256 prevBalance = ben.balance;
        stacks.mint{value: 0.005 ether}(address(nft), 1, ben, emptyProof, 0);
        assert(prevBalance - ben.balance == 0.001 ether);
        assert(nft.balanceOf(ben) == 1);

        vm.stopPrank();
    }

    /// @dev test eth sent with erc20 and get refunded
    function test_mint_erc20_with_eth() public {
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            5,
            address(coin),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        coin.approve(address(stacks), 0.001 ether);
        uint256 prevBalance = ben.balance;
        uint256 prevCoin = coin.balanceOf(ben);
        stacks.mint{value: 0.001 ether}(address(nft), 1, ben, emptyProof, 0);
        assert(prevBalance - ben.balance == 0);
        assert(nft.balanceOf(ben) == 1);
        assert(prevCoin - coin.balanceOf(ben) == 0.001 ether);
        vm.stopPrank();
    }

    /// @dev test mint for someone else and yourself
    function test_mint_for_someone_else() public {
        // eth
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            5,
            address(0),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        uint256 prevETHBalance = ben.balance;
        stacks.mint{value: 0.001 ether}(address(nft), 1, chris, emptyProof, 0);
        stacks.mint{value: 0.001 ether}(address(nft), 1, david, emptyProof, 0);
        stacks.mint{value: 0.001 ether}(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();

        assert(nft.balanceOf(chris) == 1);
        assert(nft.balanceOf(david) == 1);
        assert(nft.balanceOf(ben) == 1);
        assert(prevETHBalance - ben.balance == 0.003 ether);
        assert(stacks.get_num_minted(address(nft), chris) == 1);
        assert(stacks.get_num_minted(address(nft), david) == 1);
        assert(stacks.get_num_minted(address(nft), ben) == 1);

        vm.prank(nftOwner);
        stacks.close_drop(address(nft));

        // erc20
        vm.prank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://art.transientlabs.xyz",
            100,
            5,
            address(coin),
            nftOwner,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0.001 ether
        );

        vm.startPrank(ben);
        uint256 prevERC20Balance = coin.balanceOf(ben);
        coin.approve(address(stacks), 100 ether);
        stacks.mint(address(nft), 1, chris, emptyProof, 0);
        stacks.mint(address(nft), 1, david, emptyProof, 0);
        stacks.mint(address(nft), 1, ben, emptyProof, 0);
        vm.stopPrank();

        assert(nft.balanceOf(chris) == 2);
        assert(nft.balanceOf(david) == 2);
        assert(nft.balanceOf(ben) == 2);
        assert(prevERC20Balance - coin.balanceOf(ben) == 0.003 ether);
        assert(stacks.get_num_minted(address(nft), chris) == 1);
        assert(stacks.get_num_minted(address(nft), david) == 1);
        assert(stacks.get_num_minted(address(nft), ben) == 1);
    }

    /// @dev test eth mint
    function test_eth_mint(
        uint256 startDelay,
        uint256 presaleDuration,
        uint256 presaleCost,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        vm.assume(minter != ben && minter != chris && minter != david && minter != bsy && minter != address(0));
        vm.assume(presaleDuration > 0 || publicDuration > 0);
        if (presaleCost > 10 ether) {
            presaleCost = presaleCost % 10 ether;
        }

        if (publicCost > 10 ether) {
            publicCost = publicCost % 10 ether;
        }

        if (startDelay > 3650 days) {
            startDelay = startDelay % 3650 days;
        }

        if (presaleDuration > 3650 days) {
            presaleDuration = presaleDuration % 3650 days;
        }

        if (publicDuration > 3650 days) {
            publicDuration = publicDuration % 3650 days;
        }

        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(ben, uint256(1)));
        data[1] = keccak256(abi.encode(chris, uint256(3)));
        data[2] = keccak256(abi.encode(david, uint256(4)));
        data[3] = keccak256(abi.encode(bsy, uint256(5)));

        vm.startPrank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://arweave.net",
            100,
            4,
            address(0),
            receiver,
            block.timestamp + startDelay,
            presaleDuration,
            presaleCost,
            m.getRoot(data),
            publicDuration,
            publicCost
        );
        vm.stopPrank();

        Drop memory drop = stacks.get_drop(address(nft));

        uint256 payoutBalance = receiver.balance;
        uint256 recipientBalance = ben.balance;
        bytes32[] memory recipientProof = m.getProof(data, 0);

        // test before sale
        if (startDelay > 0) {
            vm.expectRevert("you shall not mint");
            stacks.mint(address(nft), 1, address(this), emptyProof, 0);
            vm.warp(drop.start_time);
        }

        // test presale
        if (presaleDuration > 0) {
            vm.startPrank(ben);
            vm.expectEmit(true, true, true, true);
            emit Purchase(ben, ben, address(nft), address(0), 1, presaleCost, true);
            stacks.mint{value: presaleCost}(address(nft), 1, ben, recipientProof, 1);
            assert(nft.balanceOf(ben) == 1);
            assert(recipientBalance - ben.balance == presaleCost);
            assert(receiver.balance - payoutBalance == presaleCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint{value: presaleCost}(address(nft), 1, ben, recipientProof, 1);
            vm.stopPrank();

            vm.startPrank(chris);
            recipientBalance = chris.balance;
            payoutBalance = receiver.balance;
            recipientProof = m.getProof(data, 1);
            vm.expectEmit(true, true, true, true);
            emit Purchase(chris, chris, address(nft), address(0), 2, presaleCost, true);
            stacks.mint{value: 2 * presaleCost}(address(nft), 2, chris, recipientProof, 3);
            assert(nft.balanceOf(chris) == 2);
            assert(recipientBalance - chris.balance == 2 * presaleCost);
            assert(receiver.balance - payoutBalance == 2 * presaleCost);
            recipientBalance = chris.balance;
            payoutBalance = receiver.balance;
            vm.expectEmit(true, true, true, true);
            emit Purchase(chris, chris, address(nft), address(0), 1, presaleCost, true);
            stacks.mint{value: presaleCost}(address(nft), 1, chris, recipientProof, 3);
            assert(nft.balanceOf(chris) == 3);
            assert(recipientBalance - chris.balance == presaleCost);
            assert(receiver.balance - payoutBalance == presaleCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint{value: presaleCost}(address(nft), 1, chris, recipientProof, 3);
            vm.stopPrank();

            vm.startPrank(david);
            recipientBalance = david.balance;
            payoutBalance = receiver.balance;
            recipientProof = m.getProof(data, 2);
            vm.expectEmit(true, true, true, true);
            emit Purchase(david, david, address(nft), address(0), 4, presaleCost, true);
            stacks.mint{value: 4 * presaleCost}(address(nft), 4, david, recipientProof, 4);
            assert(nft.balanceOf(david) == 4);
            assert(recipientBalance - david.balance == 4 * presaleCost);
            assert(receiver.balance - payoutBalance == 4 * presaleCost);
            vm.stopPrank();

            vm.startPrank(bsy);
            recipientBalance = bsy.balance;
            payoutBalance = receiver.balance;
            recipientProof = m.getProof(data, 3);
            vm.expectEmit(true, true, true, true);
            emit Purchase(bsy, bsy, address(nft), address(0), 5, presaleCost, true);
            stacks.mint{value: 5 * presaleCost}(address(nft), 5, bsy, recipientProof, 5);
            assert(nft.balanceOf(bsy) == 5);
            assert(recipientBalance - bsy.balance == 5 * presaleCost);
            assert(receiver.balance - payoutBalance == 5 * presaleCost);
            vm.stopPrank();

            vm.startPrank(minter);
            vm.expectRevert("not part of allowlist");
            stacks.mint{value: 5 * presaleCost}(address(nft), 5, minter, recipientProof, 5);
            vm.stopPrank();

            vm.warp(drop.start_time + drop.presale_duration);
        }

        // test public
        if (publicDuration > 0) {

            // if presale happened, check minting for those on presale
            if (presaleDuration > 0)  {
                vm.startPrank(ben);
                recipientBalance = ben.balance;
                payoutBalance = receiver.balance;
                recipientProof = m.getProof(data, 0);
                vm.expectEmit(true, true, true, true);
                emit Purchase(ben, ben, address(nft), address(0), 3, publicCost, false);
                stacks.mint{value: 3*publicCost}(address(nft), 3, ben, recipientProof, 1);
                assert(nft.balanceOf(ben) == 4);
                assert(recipientBalance - ben.balance == 3*publicCost);
                assert(receiver.balance - payoutBalance == 3*publicCost);
                vm.expectRevert("already hit mint allowance");
                stacks.mint{value: publicCost}(address(nft), 1, ben, recipientProof, 1);
                vm.stopPrank();

                vm.startPrank(chris);
                recipientBalance = chris.balance;
                payoutBalance = receiver.balance;
                recipientProof = m.getProof(data, 1);
                vm.expectEmit(true, true, true, true);
                emit Purchase(chris, chris, address(nft), address(0), 1, publicCost, false);
                stacks.mint{value: publicCost}(address(nft), 1, chris, recipientProof, 1);
                assert(nft.balanceOf(chris) == 4);
                assert(recipientBalance - chris.balance == publicCost);
                assert(receiver.balance - payoutBalance == publicCost);
                vm.expectRevert("already hit mint allowance");
                stacks.mint{value: publicCost}(address(nft), 1, chris, recipientProof, 3);
                vm.stopPrank();

                vm.startPrank(david);
                vm.expectRevert("already hit mint allowance");
                stacks.mint{value: publicCost}(address(nft), 1, david, emptyProof, 4);
                vm.stopPrank();

                vm.startPrank(bsy);
                vm.expectRevert("already hit mint allowance");
                stacks.mint{value: publicCost}(address(nft), 1, bsy, emptyProof, 5);
                vm.stopPrank();
            }

            vm.startPrank(minter);
            recipientBalance = minter.balance;
            payoutBalance = receiver.balance;
            vm.expectEmit(true, true, true, true);
            emit Purchase(minter, minter, address(nft), address(0), 3, publicCost, false);
            stacks.mint{value: 3 * publicCost}(address(nft), 3, minter, emptyProof, 0);
            assert(nft.balanceOf(minter) == 3);
            assert(recipientBalance - minter.balance == 3 * publicCost);
            assert(receiver.balance - payoutBalance == 3 * publicCost);
            recipientBalance = minter.balance;
            payoutBalance = receiver.balance;
            vm.expectEmit(true, true, true, true);
            emit Purchase(minter, minter, address(nft), address(0), 1, publicCost, false);
            stacks.mint{value: publicCost}(address(nft), 1, minter, emptyProof, 0);
            assert(nft.balanceOf(minter) == 4);
            assert(recipientBalance - minter.balance == publicCost);
            assert(receiver.balance - payoutBalance == publicCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint{value: publicCost}(address(nft), 1, minter, emptyProof, 0);
            vm.stopPrank();

            vm.warp(drop.start_time + drop.presale_duration + drop.public_duration);
        }

        vm.expectRevert("you shall not mint");
        stacks.mint(address(nft), 1, address(this), emptyProof, 0);

        drop = stacks.get_drop(address(nft));
        
        if (presaleDuration > 0 && publicDuration > 0) {
            assert(drop.supply == 100 - 21);
        } else if (presaleDuration > 0) {
            assert(drop.supply == 100 - 13);
        } else {
            assert(drop.supply == 100 - 4);
        }
    }

    /// @dev test erc20 mint
    function test_erc20_mint(
        uint256 startDelay,
        uint256 presaleDuration,
        uint256 presaleCost,
        uint256 publicDuration,
        uint256 publicCost
    ) public {
        vm.assume(minter != ben && minter != chris && minter != david && minter != bsy && minter != address(0));
        vm.assume(presaleDuration > 0 || publicDuration > 0);
        if (presaleCost > 10 ether) {
            presaleCost = presaleCost % 10 ether;
        }

        if (publicCost > 10 ether) {
            publicCost = publicCost % 10 ether;
        }

        if (startDelay > 3650 days) {
            startDelay = startDelay % 3650 days;
        }

        if (presaleDuration > 3650 days) {
            presaleDuration = presaleDuration % 3650 days;
        }

        if (publicDuration > 3650 days) {
            publicDuration = publicDuration % 3650 days;
        }

        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(ben, uint256(1)));
        data[1] = keccak256(abi.encode(chris, uint256(3)));
        data[2] = keccak256(abi.encode(david, uint256(4)));
        data[3] = keccak256(abi.encode(bsy, uint256(5)));

        vm.startPrank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://arweave.net",
            100,
            4,
            address(coin),
            receiver,
            block.timestamp + startDelay,
            presaleDuration,
            presaleCost,
            m.getRoot(data),
            publicDuration,
            publicCost
        );
        vm.stopPrank();

        Drop memory drop = stacks.get_drop(address(nft));

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

        uint256 payoutBalance = coin.balanceOf(receiver);
        uint256 recipientBalance = coin.balanceOf(ben);
        bytes32[] memory recipientProof = m.getProof(data, 0);

        // test before sale
        if (startDelay > 0) {
            vm.expectRevert("you shall not mint");
            stacks.mint(address(nft), 1, address(this), emptyProof, 0);
            vm.warp(drop.start_time);
        }

        // test presale
        if (presaleDuration > 0) {
            vm.startPrank(ben);
            vm.expectEmit(true, true, true, true);
            emit Purchase(ben, ben, address(nft), address(coin), 1, presaleCost, true);
            stacks.mint(address(nft), 1, ben, recipientProof, 1);
            assert(nft.balanceOf(ben) == 1);
            assert(recipientBalance - coin.balanceOf(ben) == presaleCost);
            assert(coin.balanceOf(receiver) - payoutBalance == presaleCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint(address(nft), 1, ben, recipientProof, 1);
            vm.stopPrank();

            vm.startPrank(chris);
            recipientBalance = coin.balanceOf(chris);
            payoutBalance = coin.balanceOf(receiver);
            recipientProof = m.getProof(data, 1);
            vm.expectEmit(true, true, true, true);
            emit Purchase(chris, chris, address(nft), address(coin), 2, presaleCost, true);
            stacks.mint(address(nft), 2, chris, recipientProof, 3);
            assert(nft.balanceOf(chris) == 2);
            assert(recipientBalance - coin.balanceOf(chris) == 2 * presaleCost);
            assert(coin.balanceOf(receiver) - payoutBalance == 2 * presaleCost);
            recipientBalance = coin.balanceOf(chris);
            payoutBalance = coin.balanceOf(receiver);
            vm.expectEmit(true, true, true, true);
            emit Purchase(chris, chris, address(nft), address(coin), 1, presaleCost, true);
            stacks.mint(address(nft), 1, chris, recipientProof, 3);
            assert(nft.balanceOf(chris) == 3);
            assert(recipientBalance - coin.balanceOf(chris) == presaleCost);
            assert(coin.balanceOf(receiver) - payoutBalance == presaleCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint(address(nft), 1, chris, recipientProof, 3);
            vm.stopPrank();

            vm.startPrank(david);
            recipientBalance = coin.balanceOf(david);
            payoutBalance = coin.balanceOf(receiver);
            recipientProof = m.getProof(data, 2);
            vm.expectEmit(true, true, true, true);
            emit Purchase(david, david, address(nft), address(coin), 4, presaleCost, true);
            stacks.mint(address(nft), 4, david, recipientProof, 4);
            assert(nft.balanceOf(david) == 4);
            assert(recipientBalance - coin.balanceOf(david) == 4 * presaleCost);
            assert(coin.balanceOf(receiver) - payoutBalance == 4 * presaleCost);
            vm.stopPrank();

            vm.startPrank(bsy);
            recipientBalance = coin.balanceOf(bsy);
            payoutBalance = coin.balanceOf(receiver);
            recipientProof = m.getProof(data, 3);
            vm.expectEmit(true, true, true, true);
            emit Purchase(bsy, bsy, address(nft), address(coin), 5, presaleCost, true);
            stacks.mint(address(nft), 5, bsy, recipientProof, 5);
            assert(nft.balanceOf(bsy) == 5);
            assert(recipientBalance - coin.balanceOf(bsy) == 5 * presaleCost);
            assert(coin.balanceOf(receiver) - payoutBalance == 5 * presaleCost);
            vm.stopPrank();

            vm.startPrank(minter);
            vm.expectRevert("not part of allowlist");
            stacks.mint(address(nft), 5, minter, recipientProof, 5);
            vm.stopPrank();

            vm.warp(drop.start_time + drop.presale_duration);
        }

        // test public
        if (publicDuration > 0) {

            // if presale happened, check minting for those on presale
            if (presaleDuration > 0)  {
                vm.startPrank(ben);
                recipientBalance = coin.balanceOf(ben);
                payoutBalance = coin.balanceOf(receiver);
                recipientProof = m.getProof(data, 0);
                vm.expectEmit(true, true, true, true);
                emit Purchase(ben, ben, address(nft), address(coin), 3, publicCost, false);
                stacks.mint(address(nft), 3, ben, recipientProof, 1);
                assert(nft.balanceOf(ben) == 4);
                assert(recipientBalance - coin.balanceOf(ben) == 3*publicCost);
                assert(coin.balanceOf(receiver) - payoutBalance == 3*publicCost);
                vm.expectRevert("already hit mint allowance");
                stacks.mint(address(nft), 1, ben, recipientProof, 1);
                vm.stopPrank();

                vm.startPrank(chris);
                recipientBalance = coin.balanceOf(chris);
                payoutBalance = coin.balanceOf(receiver);
                recipientProof = m.getProof(data, 1);
                vm.expectEmit(true, true, true, true);
                emit Purchase(chris, chris, address(nft), address(coin), 1, publicCost, false);
                stacks.mint(address(nft), 1, chris, recipientProof, 1);
                assert(nft.balanceOf(chris) == 4);
                assert(recipientBalance - coin.balanceOf(chris) == publicCost);
                assert(coin.balanceOf(receiver) - payoutBalance == publicCost);
                vm.expectRevert("already hit mint allowance");
                stacks.mint(address(nft), 1, chris, recipientProof, 3);
                vm.stopPrank();

                vm.startPrank(david);
                vm.expectRevert("already hit mint allowance");
                stacks.mint(address(nft), 1, david, emptyProof, 4);
                vm.stopPrank();

                vm.startPrank(bsy);
                vm.expectRevert("already hit mint allowance");
                stacks.mint(address(nft), 1, bsy, emptyProof, 5);
                vm.stopPrank();
            }

            vm.startPrank(minter);
            recipientBalance = coin.balanceOf(minter);
            payoutBalance = coin.balanceOf(receiver);
            vm.expectEmit(true, true, true, true);
            emit Purchase(minter, minter, address(nft), address(coin), 3, publicCost, false);
            stacks.mint(address(nft), 3, minter, emptyProof, 0);
            assert(nft.balanceOf(minter) == 3);
            assert(recipientBalance - coin.balanceOf(minter) == 3 * publicCost);
            assert(coin.balanceOf(receiver) - payoutBalance == 3 * publicCost);
            recipientBalance = coin.balanceOf(minter);
            payoutBalance = coin.balanceOf(receiver);
            vm.expectEmit(true, true, true, true);
            emit Purchase(minter, minter, address(nft), address(coin), 1, publicCost, false);
            stacks.mint(address(nft), 1, minter, emptyProof, 0);
            assert(nft.balanceOf(minter) == 4);
            assert(recipientBalance - coin.balanceOf(minter) == publicCost);
            assert(coin.balanceOf(receiver) - payoutBalance == publicCost);
            vm.expectRevert("already hit mint allowance");
            stacks.mint(address(nft), 1, minter, emptyProof, 0);
            vm.stopPrank();

            vm.warp(drop.start_time + drop.presale_duration + drop.public_duration);
        }

        vm.expectRevert("you shall not mint");
        stacks.mint(address(nft), 1, address(this), emptyProof, 0);

        drop = stacks.get_drop(address(nft));
        
        if (presaleDuration > 0 && publicDuration > 0) {
            assert(drop.supply == 100 - 21);
        } else if (presaleDuration > 0) {
            assert(drop.supply == 100 - 13);
        } else {
            assert(drop.supply == 100 - 4);
        }
    }

    /// @dev test two mints going on at the same time on separate contracts
    function test_two_mints_going_on_simultaneously() public {
        vm.startPrank(nftOwner);
        stacks.configure_drop(
            address(nft),
            "https://arweave.net/1",
            100,
            10,
            address(0),
            receiver,
            block.timestamp,
            0,
            0,
            bytes32(0),
            3600,
            0
        );
        
        stacks.configure_drop(
            address(nftTwo),
            "https://arweave.net/2",
            100,
            10,
            address(0),
            receiver,
            block.timestamp + 3600,
            0,
            0,
            bytes32(0),
            3600,
            0
        );
        vm.stopPrank();

        assert(stacks.get_drop_phase(address(nft)) == DropPhase.PUBLIC_SALE);
        assert(stacks.get_drop_phase(address(nftTwo)) == DropPhase.BEFORE_SALE);

        stacks.mint(address(nft), 1, address(this), emptyProof, 0);
        assert(stacks.get_num_minted(address(nft), address(this)) == 1);
        assert(stacks.get_num_minted(address(nftTwo), address(this)) == 0);

        vm.warp(block.timestamp + 3600);

        assert(stacks.get_drop_phase(address(nft)) == DropPhase.ENDED);
        assert(stacks.get_drop_phase(address(nftTwo)) == DropPhase.PUBLIC_SALE);

        stacks.mint(address(nftTwo), 5, address(this), emptyProof, 0);

        assert(stacks.get_num_minted(address(nft), address(this)) == 1);
        assert(stacks.get_num_minted(address(nftTwo), address(this)) == 5);
    }
}

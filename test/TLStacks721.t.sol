// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";

import {TLStacks721, Drop, ITLStacks721} from "tl-stacks/TLStacks721.sol";
import {ITLStacks721Events} from "tl-stacks/utils/ITLStacks721Events.sol";

import {ERC721TL} from "tl-core/core/ERC721TL.sol";

import {ERC20PresetMinterPauserUpgradeable} from "openzeppelin-upgradeable/token/ERC20/presets/ERC20PresetMinterPauserUpgradeable.sol";

contract Receiver {
    fallback() external {
        revert();
    }

    receive() external payable {}
}

contract TLStacks721Test is Test, ITLStacks721Events {
    TLStacks721 mintingContract;
    ERC721TL nft;
    ERC20PresetMinterPauserUpgradeable erc20;

    address mintingOwner = address(0xdead);

    address alice = address(0xbeef);
    address bob = address(0x1337);
    address charles = address(0xcafe);
    address david = address(0xcdb);

    function setUp() public {
        mintingContract = new TLStacks721(false);
        mintingContract.initialize(mintingOwner);

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(mintingContract);

        nft = new ERC721TL(false);
        nft.initialize(
            "Karl",
            "LFG",
            alice,
            1_000,
            alice,
            empty,
            false,
            address(0)
        );

        assert(nft.owner() == alice);

        vm.startPrank(alice);
        nft.setApprovedMintContracts(mintAddrs, true);
        erc20 = new ERC20PresetMinterPauserUpgradeable();
        erc20.initialize("money", "MONEY");
        erc20.mint(alice, 10000 * 10**18);
        erc20.transfer(bob, 2000 * 10**18);
        erc20.transfer(charles, 2000 * 10**18);
        erc20.transfer(david, 2000 * 10**18);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charles, 100 ether);
        vm.deal(david, 100 ether);

        vm.prank(alice);
        erc20.approve(address(mintingContract), type(uint256).max);

        vm.prank(bob);
        erc20.approve(address(mintingContract), type(uint256).max);

        vm.prank(charles);
        erc20.approve(address(mintingContract), type(uint256).max);

        vm.prank(david);
        erc20.approve(address(mintingContract), type(uint256).max);
    }

    function setup_open_edition_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        address _currencyAddr
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configureDrop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            0,
            5,
            alice,
            _startTime,
            _presaleDuration,
            _currencyAddr,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.getDrop(address(nft));
    }

    function setup_open_edition_mint_with_receiver(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        address _receiver,
        address _currencyAddr
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configureDrop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            0,
            5,
            _receiver,
            _startTime,
            _presaleDuration,
            _currencyAddr,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.getDrop(address(nft));
    }

    function setup_limited_edition_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        uint256 _supply,
        address _currencyAddr
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configureDrop(
            address(nft),
            "testBaseUri/",
            _supply,
            0,
            5,
            alice,
            _startTime,
            _presaleDuration,
            _currencyAddr,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.getDrop(address(nft));
    }

    function setup_velocity_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        int256 _decay_rate,
        address _currencyAddr
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configureDrop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            _decay_rate,
            5,
            alice,
            _startTime,
            _presaleDuration,
            _currencyAddr,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.getDrop(address(nft));
    }

    function test_init() public view {
        // Arrange
        bytes32 mintingContractRole = keccak256("APPROVED_MINT_CONTRACT");

        // Act
        address owner = mintingContract.owner();
        bool hasRole = nft.hasRole(
            mintingContractRole,
            address(mintingContract)
        );

        // Assert
        assert(owner == mintingOwner);
        assert(hasRole);
    }

    function test_open_edition_mint_to() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("not enough funds sent");
        mintingContract.mint(address(nft), 1, bob, emptyProof, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.08 ether);
        assert(alice.balance == 100 ether + 0.08 ether);
        assert(nft.balanceOf(bob) == 4);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.04 ether}(
            address(nft),
            2,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.1 ether);
        assert(alice.balance == 100 ether + 0.1 ether);
        assert(nft.balanceOf(bob) == 5);

        vm.startPrank(bob);
        vm.expectRevert("already hit mint allowance");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        vm.warp(
            drop.startTime + drop.presaleDuration + drop.publicDuration + 1
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(mintingContract.getDropPhase(address(nft)) == ITLStacks721.DropPhase.ENDED);
    }

    function test_open_edition_no_presale() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            address(0)
        );

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, charles, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 0);
        assert(nft.balanceOf(charles) == 1);
    }

    function test_limited_edition_no_presale_mint_out() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_limited_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            9,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 5, .02 ether, false);
        mintingContract.mint{value: 0.1 ether}(
            address(nft),
            5,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(bob.balance == 100 ether - 0.1 ether);
        assert(alice.balance == 100 ether + 0.1 ether);
        assert(nft.balanceOf(bob) == 5);
        assert(drop.supply == 4);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), address(0), 4, .02 ether, false);
        mintingContract.mint{value: 0.1 ether}(
            address(nft),
            5,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(charles.balance == 100 ether - 0.08 ether);
        assert(nft.balanceOf(charles) == 4);
        assert(drop.supply == 0);

        vm.startPrank(bob);
        vm.expectRevert("no supply left");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(mintingContract.getDropPhase(address(nft)) == ITLStacks721.DropPhase.ENDED);
    }

    function test_limited_edition_no_presale_time_expired() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_limited_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            9,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(bob.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.06 ether);
        assert(nft.balanceOf(bob) == 3);
        assert(drop.supply == 6);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.supply == 3);

        vm.warp(
            drop.startTime + drop.presaleDuration + drop.publicDuration + 1
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(mintingContract.getDropPhase(address(nft)) == ITLStacks721.DropPhase.ENDED);
    }

    function test_velocity_mint() public {
        bytes32[] memory emptyProof;

        uint256 startTime = block.timestamp;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_velocity_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            30 minutes,
            -5 minutes,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(drop.publicDuration == 30 minutes);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(drop.publicDuration == 25 minutes);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.08 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.publicDuration == 10 minutes);

        vm.startPrank(david);
        vm.expectEmit(true, true, false, true);
        emit Purchase(david, david, address(nft), address(0), 2, .02 ether, false);
        mintingContract.mint{value: 0.04 ether}(
            address(nft),
            2,
            david,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(david.balance == 100 ether - 0.04 ether);
        assert(alice.balance == 100 ether + 0.12 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(nft.balanceOf(david) == 2);
        assert(drop.publicDuration == 0);

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(mintingContract.getDropPhase(address(nft)) == ITLStacks721.DropPhase.ENDED);

        uint256 endTime = block.timestamp;

        assert(endTime - startTime < 30 minutes);
    }

    function test_open_edition_presale() public {
        bytes32[] memory emptyProof;

        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(alice, uint256(1)));
        data[1] = keccak256(abi.encodePacked(bob, uint256(3)));
        data[2] = keccak256(abi.encodePacked(charles, uint256(4)));
        data[3] = keccak256(abi.encodePacked(david, uint256(5)));
        bytes32 root = m.getRoot(data);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            500,
            false,
            root,
            1 days,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        vm.warp(drop.startTime + 1);

        assert(
            mintingContract.getDropPhase(address(nft)) == ITLStacks721.DropPhase.PRESALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .01 ether, true);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            m.getProof(data, 1),
            3
        );
        vm.stopPrank();

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("not enough funds sent");
        mintingContract.mint(address(nft), 1, bob, emptyProof, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.03 ether);
        assert(alice.balance == 100 ether + 0.03 ether);
        assert(nft.balanceOf(bob) == 2);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();
    }

    function test_open_edition_with_contract_payout() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        address receiver = address(new Receiver());

        Drop memory drop = setup_open_edition_mint_with_receiver(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            receiver,
            address(0)
        );

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(receiver.balance == 0.02 ether);
        assert(nft.balanceOf(bob) == 1);

    }

    function test_marathon_mint() public {
        bytes32[] memory emptyProof;

        uint256 startTime = block.timestamp;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_velocity_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            30 minutes,
            5 minutes,
            address(0)
        );

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.BEFORE_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("you shall not mint");
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        assert(drop.publicDuration == 30 minutes);

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), address(0), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(drop.publicDuration == 35 minutes);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), address(0), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.08 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.publicDuration == 50 minutes);

        vm.startPrank(david);
        vm.expectEmit(true, true, false, true);
        emit Purchase(david, david, address(nft), address(0), 2, .02 ether, false);
        mintingContract.mint{value: 0.04 ether}(
            address(nft),
            2,
            david,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.getDrop(address(nft));

        assert(david.balance == 100 ether - 0.04 ether);
        assert(alice.balance == 100 ether + 0.12 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(nft.balanceOf(david) == 2);
        assert(drop.publicDuration == 60 minutes);

        uint256 endTime = drop.startTime + drop.presaleDuration + drop.publicDuration;

        assert(endTime - startTime > 30 minutes);
    }

    function test_open_edition_no_presale_erc20() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.getDropPhase(address(nft)) ==
                ITLStacks721.DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            address(erc20)
        );

        vm.warp(drop.startTime + drop.presaleDuration + 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, charles, address(nft), address(erc20), 1, .02 ether, false);
        mintingContract.mint(
            address(nft),
            1,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        assert(erc20.balanceOf(bob) == 1999980000000000000000);
        assert(erc20.balanceOf(alice) == 4000020000000000000000);
        assert(nft.balanceOf(bob) == 0);
        assert(nft.balanceOf(charles) == 1);
    }
}

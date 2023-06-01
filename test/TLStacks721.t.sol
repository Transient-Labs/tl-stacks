// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";
import {Merkle} from "murky/Merkle.sol";

import {ITLStacks721, Drop} from "tl-stacks/ITLStacks721.sol";
import {ITLStacks721Events} from "tl-stacks/utils/ITLStacks721Events.sol";
import {DropPhase, DropParam} from "tl-stacks/utils/DropUtils.sol";

import {ERC721TL} from "tl-creator-contracts/ERC721TL.sol";

contract Receiver {
    fallback() external {
        revert();
    }

    receive() external payable {}
}

contract TLStacks721Test is Test, ITLStacks721Events {
    VyperDeployer vyperDeployer = new VyperDeployer();

    ITLStacks721 mintingContract;
    ERC721TL nft;

    address mintingOwner = address(0xdead);

    address alice = address(0xbeef);
    address bob = address(0x1337);
    address charles = address(0xcafe);
    address david = address(0xcdb);

    function setUp() public {
        mintingContract = ITLStacks721(
            vyperDeployer.deployContract(
                "TLStacks721",
                abi.encode(mintingOwner)
            )
        );

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(mintingContract);

        address[] memory addrs = new address[](1);
        addrs[0] = alice;

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

        vm.startPrank(alice);
        nft.setApprovedMintContracts(mintAddrs, true);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charles, 100 ether);
        vm.deal(david, 100 ether);
    }

    function setup_open_edition_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configure_drop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            0,
            5,
            alice,
            _startTime,
            _presaleDuration,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.get_drop(address(nft));
    }

    function setup_open_edition_mint_with_receiver(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        address _receiver
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configure_drop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            0,
            5,
            _receiver,
            _startTime,
            _presaleDuration,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.get_drop(address(nft));
    }

    function setup_limited_edition_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        uint256 _supply
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configure_drop(
            address(nft),
            "testBaseUri/",
            _supply,
            0,
            5,
            alice,
            _startTime,
            _presaleDuration,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.get_drop(address(nft));
    }

    function setup_velocity_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration,
        int256 _decay_rate
    ) internal returns (Drop memory) {
        vm.prank(alice);
        mintingContract.configure_drop(
            address(nft),
            "testBaseUri/",
            type(uint256).max,
            _decay_rate,
            5,
            alice,
            _startTime,
            _presaleDuration,
            .01 ether,
            _presaleRoot,
            _publicDuration,
            .02 ether
        );

        if (_warpToPublicSale) {
            vm.warp(_startTime + _presaleDuration);
        }

        return mintingContract.get_drop(address(nft));
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
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
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

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("not enough funds sent");
        mintingContract.mint(address(nft), 1, bob, emptyProof, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
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
        emit Purchase(bob, bob, address(nft), 3, .02 ether, false);
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
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
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
            drop.start_time + drop.presale_duration + drop.public_duration + 1
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

        assert(mintingContract.get_drop_phase(address(nft)) == DropPhase.ENDED);
    }

    function test_open_edition_no_presale() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days
        );

        vm.warp(drop.start_time + drop.presale_duration + 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, charles, address(nft), 1, .02 ether, false);
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
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_limited_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            9
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
        );

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 5, .02 ether, false);
        mintingContract.mint{value: 0.1 ether}(
            address(nft),
            5,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(bob.balance == 100 ether - 0.1 ether);
        assert(alice.balance == 100 ether + 0.1 ether);
        assert(nft.balanceOf(bob) == 5);
        assert(drop.supply == 4);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), 4, .02 ether, false);
        mintingContract.mint{value: 0.1 ether}(
            address(nft),
            5,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

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

        assert(mintingContract.get_drop_phase(address(nft)) == DropPhase.ENDED);
    }

    function test_limited_edition_no_presale_time_expired() public {
        bytes32[] memory emptyProof;

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_limited_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            9
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
        );

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(bob.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.06 ether);
        assert(nft.balanceOf(bob) == 3);
        assert(drop.supply == 6);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.supply == 3);

        vm.warp(
            drop.start_time + drop.presale_duration + drop.public_duration + 1
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

        assert(mintingContract.get_drop_phase(address(nft)) == DropPhase.ENDED);
    }

    function test_velocity_mint() public {
        bytes32[] memory emptyProof;

        uint256 startTime = block.timestamp;

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_velocity_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            30 minutes,
            -5 minutes
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
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

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(drop.public_duration == 30 minutes);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(drop.public_duration == 25 minutes);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.08 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.public_duration == 10 minutes);

        vm.startPrank(david);
        vm.expectEmit(true, true, false, true);
        emit Purchase(david, david, address(nft), 2, .02 ether, false);
        mintingContract.mint{value: 0.04 ether}(
            address(nft),
            2,
            david,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(david.balance == 100 ether - 0.04 ether);
        assert(alice.balance == 100 ether + 0.12 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(nft.balanceOf(david) == 2);
        assert(drop.public_duration == 0);

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

        assert(mintingContract.get_drop_phase(address(nft)) == DropPhase.ENDED);

        uint256 endTime = block.timestamp;

        assert(endTime - startTime < 30 minutes);
    }

    function test_open_edition_presale() public {
        bytes32[] memory emptyProof;

        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(alice, uint256(1)));
        data[1] = keccak256(abi.encode(bob, uint256(3)));
        data[2] = keccak256(abi.encode(charles, uint256(4)));
        data[3] = keccak256(abi.encode(david, uint256(5)));
        bytes32 root = m.getRoot(data);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_open_edition_mint(
            block.timestamp + 300,
            500,
            false,
            root,
            1 days
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
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

        vm.warp(drop.start_time + 1);

        assert(
            mintingContract.get_drop_phase(address(nft)) == DropPhase.PRESALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .01 ether, true);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            m.getProof(data, 1),
            3
        );
        vm.stopPrank();

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectRevert("not enough funds sent");
        mintingContract.mint(address(nft), 1, bob, emptyProof, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
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
        emit Purchase(bob, bob, address(nft), 3, .02 ether, false);
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
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        address receiver = address(new Receiver());

        Drop memory drop = setup_open_edition_mint_with_receiver(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days,
            receiver
        );

        vm.warp(drop.start_time + drop.presale_duration + 1);

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
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
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.NOT_CONFIGURED
        );

        Drop memory drop = setup_velocity_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            30 minutes,
            5 minutes
        );

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.BEFORE_SALE
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

        vm.warp(drop.start_time + drop.presale_duration + 1);

        assert(drop.public_duration == 30 minutes);

        assert(
            mintingContract.get_drop_phase(address(nft)) ==
                DropPhase.PUBLIC_SALE
        );

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit Purchase(bob, bob, address(nft), 1, .02 ether, false);
        mintingContract.mint{value: 0.02 ether}(
            address(nft),
            1,
            bob,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(bob.balance == 100 ether - 0.02 ether);
        assert(alice.balance == 100 ether + 0.02 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(drop.public_duration == 35 minutes);

        vm.startPrank(charles);
        vm.expectEmit(true, true, false, true);
        emit Purchase(charles, charles, address(nft), 3, .02 ether, false);
        mintingContract.mint{value: 0.06 ether}(
            address(nft),
            3,
            charles,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(charles.balance == 100 ether - 0.06 ether);
        assert(alice.balance == 100 ether + 0.08 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(drop.public_duration == 50 minutes);

        vm.startPrank(david);
        vm.expectEmit(true, true, false, true);
        emit Purchase(david, david, address(nft), 2, .02 ether, false);
        mintingContract.mint{value: 0.04 ether}(
            address(nft),
            2,
            david,
            emptyProof,
            0
        );
        vm.stopPrank();

        drop = mintingContract.get_drop(address(nft));

        assert(david.balance == 100 ether - 0.04 ether);
        assert(alice.balance == 100 ether + 0.12 ether);
        assert(nft.balanceOf(bob) == 1);
        assert(nft.balanceOf(charles) == 3);
        assert(nft.balanceOf(david) == 2);
        assert(drop.public_duration == 60 minutes);

        uint256 endTime = drop.start_time + drop.presale_duration + drop.public_duration;

        assert(endTime - startTime > 30 minutes);
    }
}

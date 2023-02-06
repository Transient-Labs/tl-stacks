// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";

import {IEditionMinting1155, Drop, DropPhase, DropParam} from "../IEditionMinting1155.sol";

import {ERC1155TL} from "tl-core/ERC1155TL.sol";

contract EditionMinting1155Test is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();

    IEditionMinting1155 mintingContract;
    ERC1155TL nft;

    address mintingOwner = address(0xdead);

    address alice = address(0xbeef);
    address bob = address(0x1337);
    address charles = address(0xcafe);

    function setUp() public {
        mintingContract = IEditionMinting1155(
            vyperDeployer.deployContract(
                "EditionMinting1155",
                abi.encode(mintingOwner)
            )
        );

        address[] memory empty = new address[](0);
        address[] memory mintAddrs = new address[](1);
        mintAddrs[0] = address(mintingContract);

        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        uint256[] memory amts = new uint256[](1);

        nft = new ERC1155TL(false);
        nft.initialize("Karl", alice, 1_000, alice, empty, false, address(0));

        vm.startPrank(alice);
        nft.setApprovedMintContracts(mintAddrs, true);
        nft.createToken("ipfs://URI/", addrs, amts);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charles, 100 ether);
    }

    function setup_open_edition_mint(
        uint256 _startTime,
        uint256 _presaleDuration,
        bool _warpToPublicSale,
        bytes32 _presaleRoot,
        uint256 _publicDuration
    ) public {
        vm.prank(alice);
        mintingContract.configure_drop(
            address(nft),
            1,
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

    function test_open_edition_no_presale() public {
        setup_open_edition_mint(
            block.timestamp + 300,
            0,
            false,
            bytes32(0),
            1 days
        );

        Drop memory drop = mintingContract.get_drop(address(nft), 1);
        // assert(false);
        

        // emit log_uint(drop.start_time);
        // assert(
        //     mintingContract.get_drop_phase(address(nft), 1) ==
        //         DropPhase.NOT_CONFIGURED
        // );


        // assert(
        //     mintingContract.get_drop_phase(address(nft), 1) ==
        //         DropPhase.BEFORE_SALE
        // );
    }
}

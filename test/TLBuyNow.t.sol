// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";

import {ITLBuyNowEvents, ITLBuyNow, Sale} from "tl-stacks/utils/ITLBuyNow.sol";

import {TLCreator} from "tl-creator-contracts/TLCreator.sol";
import {ERC721TL} from "tl-creator-contracts/core/ERC721TL.sol";

import {Receiver} from "./utils/Receiver.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract TLBuyNowTest is Test, ITLBuyNowEvents {
    VyperDeployer vyperDeployer = new VyperDeployer();

    ITLBuyNow bn;
    ERC721TL nft;
    MockERC20 coin;

    address nftOwner = address(0xABC);
    address receiver;

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);
    address bsy = address(0xCDB);

    function setUp() public {
        bn = ITLBuyNow(vyperDeployer.deployContract("TLBuyNow", abi.encode(address(this))));

        address[] memory empty = new address[](0);

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
        vm.startPrank(nftOwner);
        nft.mint(ben, "sick ass token 1");
        nft.mint(chris, "sick ass token 2");
        nft.mint(david, "sick ass token 3");
        nft.mint(bsy, "sick ass token 4");
        vm.stopPrank();

        coin = new MockERC20(address(this));
        coin.transfer(ben, 100 ether);
        coin.transfer(chris, 100 ether);
        coin.transfer(david, 100 ether);
        coin.transfer(bsy, 100 ether);

        receiver = address(new Receiver());

        vm.deal(ben, 100 ether);
        vm.deal(chris, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(bsy, 100 ether);

        vm.prank(ben);
        nft.setApprovalForAll(address(bn), true);
        vm.prank(chris);
        nft.setApprovalForAll(address(bn), true);
        vm.prank(david);
        nft.setApprovalForAll(address(bn), true);
        vm.prank(bsy);
        nft.setApprovalForAll(address(bn), true);
    }

    /// @dev test constructor setup
    function test_setUp() public {
        assert(bn.owner() == address(this));
        assertFalse(bn.paused());
    }

    /// @dev test owner only access for owner functions
    /// @dev reverts if not the owner
    function test_owner_only_access(address sender) public {
        vm.assume(sender != address(this));
        vm.startPrank(sender);
        vm.expectRevert("caller not owner");
        bn.set_paused(true);
        vm.expectRevert("caller not owner");
        bn.set_paused(false);
        vm.expectRevert("caller not owner");
        bn.transfer_ownership(sender);
        vm.expectRevert("caller not owner");
        bn.update_royalty_engine(address(0));
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
        bn.transfer_ownership(newOwner);
        assert(bn.owner() == newOwner);
        vm.expectRevert("caller not owner");
        bn.set_paused(true);
    }

    /// @dev test paused functionality
    function test_paused() public {
        bn.set_paused(true);

        vm.startPrank(ben);

        vm.expectRevert("contract is paused");
        bn.configure_sale(address(nft), 1, ben, address(0), 1 ether);

        vm.expectRevert("contract is paused");
        bn.update_sale_price(address(nft), 1, address(0), 1 ether);

        vm.expectRevert("contract is paused");
        bn.buy(address(nft), 2);

        vm.stopPrank();
    }

    /// @dev check only nft owner can configure sales
    function test_configure_sale_not_token_owner(address hacker) public {
        vm.assume(
            hacker != ben &&
            hacker != chris &&
            hacker != david &&
            hacker != bsy
        );

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 1, hacker, address(0), 1 ether);

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 2, hacker, address(0), 1 ether);

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 3, hacker, address(0), 1 ether);

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 4, hacker, address(0), 1 ether);
    }

    /// @dev check that configuration of the sale reverts if the contract isn't approved
    function test_configure_sale_not_approved(address seller) public {
        vm.assume(
            seller != ben &&
            seller != chris &&
            seller != david &&
            seller != bsy
        );

        vm.prank(nftOwner);
        nft.mint(seller, "sick ass token 5");

        vm.startPrank(seller);
        vm.expectRevert("caller does not have the contract approved for the token");
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether);

        nft.approve(address(bn), 5);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(seller, address(nft), 5, Sale(seller, seller, address(0), 1 ether));
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether);

        nft.approve(address(0), 5);

        nft.setApprovalForAll(address(bn), true);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(seller, address(nft), 5, Sale(seller, seller, address(0), 1 ether));
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether);
        
        vm.stopPrank();
    }
}

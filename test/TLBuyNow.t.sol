// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";
import {Merkle} from "murky/Merkle.sol";

import {ITLBuyNowEvents, ITLBuyNow, Sale} from "tl-stacks/utils/ITLBuyNow.sol";
import {IRoyaltyEngine} from "tl-stacks/utils/IRoyaltyEngine.sol";

import {TLCreator} from "tl-creator-contracts/TLCreator.sol";
import {ERC721TL} from "tl-creator-contracts/core/ERC721TL.sol";

import {Receiver, RevertingReceiver} from "./utils/Receiver.sol";
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

    address royaltyEngine = 0x0385603ab55642cb4Dd5De3aE9e306809991804f;

    address[] empty = new address[](0);
    bytes32[] emptyProof = new bytes32[](0);

    function setUp() public {
        bn = ITLBuyNow(vyperDeployer.deployContract("TLBuyNow", abi.encode(address(this), royaltyEngine)));

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
        assert(bn.royalty_engine() == royaltyEngine);
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

    /// @dev test update royalty engine
    function test_update_royalty_engine() public {
        vm.expectEmit(true, true, false, false);
        emit RoyaltyEngineUpdated(royaltyEngine, address(1));
        bn.update_royalty_engine(address(1));
        assert(bn.royalty_engine() == address(1));
    }

    /// @dev test paused functionality
    function test_paused() public {
        bn.set_paused(true);

        vm.startPrank(ben);

        vm.expectRevert("contract is paused");
        bn.configure_sale(address(nft), 1, ben, address(0), 1 ether, bytes32(0));

        vm.expectRevert("contract is paused");
        bn.update_sale_price(address(nft), 1, address(0), 1 ether);

        vm.expectRevert("contract is paused");
        bn.update_merkle_root(address(nft), 1, bytes32(uint256(1)));

        vm.expectRevert("contract is paused");
        bn.buy(address(nft), 2, address(this), emptyProof);

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
        bn.configure_sale(address(nft), 1, hacker, address(0), 1 ether, bytes32(0));

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 2, hacker, address(0), 1 ether, bytes32(0));

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 3, hacker, address(0), 1 ether, bytes32(0));

        vm.expectRevert("caller is not the token owner");
        bn.configure_sale(address(nft), 4, hacker, address(0), 1 ether, bytes32(0));
    }

    /// @dev check that configuration of the sale reverts if the contract isn't approved
    function test_configure_sale_not_approved(address seller) public {
        vm.assume(
            seller != ben &&
            seller != chris &&
            seller != david &&
            seller != bsy &&
            seller != address(0)
        );

        vm.prank(nftOwner);
        nft.mint(seller, "sick ass token 5");

        vm.startPrank(seller);
        vm.expectRevert("caller does not have the contract approved for the token");
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether, bytes32(0));

        nft.approve(address(bn), 5);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(seller, address(nft), 5, Sale(seller, seller, address(0), 1 ether, bytes32(0)));
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether, bytes32(0));

        nft.approve(address(0), 5);

        nft.setApprovalForAll(address(bn), true);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(seller, address(nft), 5, Sale(seller, seller, address(0), 1 ether, bytes32(0)));
        bn.configure_sale(address(nft), 5, seller, address(0), 1 ether, bytes32(0));
        
        vm.stopPrank();
    }

    /// @dev test configuration of the sale
    function test_configure_sale(
        address payoutReceiver,
        address currencyAddr,
        uint256 price,
        bytes32 merkleRoot
    ) public {
        vm.startPrank(ben);
        vm.expectEmit(true, true, true, true);
        emit SaleConfigured(ben, address(nft), 1, Sale(ben, payoutReceiver, currencyAddr, price, merkleRoot));
        bn.configure_sale(address(nft), 1, payoutReceiver, currencyAddr, price, merkleRoot);
        Sale memory sale = bn.get_sale(address(nft), 1);
        assert(sale.seller == ben);
        assert(sale.payout_receiver == payoutReceiver);
        assert(sale.currency_addr == currencyAddr);
        assert(sale.price == price);
        assert(sale.merkle_root == merkleRoot);
        vm.stopPrank();
    }

    /// @dev check that the original seller is the only one that can adjust price and merkle root on a sale
    function test_change_price_merkle_root_access(address hacker) public {
        vm.assume(hacker != ben);
        vm.prank(ben);
        bn.configure_sale(address(nft), 1, ben, address(0), 1 ether, bytes32(0));
        
        vm.startPrank(hacker);
        vm.expectRevert("caller is not the token seller");
        bn.update_sale_price(address(nft), 1, address(coin), 0 ether);

        vm.expectRevert("caller is not the token seller");
        bn.update_merkle_root(address(nft), 1, bytes32(uint256(3)));
        vm.stopPrank();

        vm.startPrank(ben);
        vm.expectEmit(true, true, true, true);
        emit SaleUpdated(ben, address(nft), 1, Sale(ben, ben, address(coin), 0 ether, bytes32(0)));
        bn.update_sale_price(address(nft), 1, address(coin), 0 ether);

        vm.expectEmit(true, true, true, true);
        emit SaleUpdated(ben, address(nft), 1, Sale(ben, ben, address(coin), 0 ether, bytes32(uint256(1))));
        bn.update_merkle_root(address(nft), 1, bytes32(uint256(1)));
        vm.stopPrank();

        Sale memory sale = bn.get_sale(address(nft), 1);
        assert(sale.seller == ben);
        assert(sale.payout_receiver == ben);
        assert(sale.currency_addr == address(coin));
        assert(sale.price == 0 ether);
        assert(sale.merkle_root == bytes32(uint256(1)));
    }

    /// @dev test cancel sale
    function test_cancel_sale(address hacker) public {
        vm.assume(hacker != ben);

        vm.prank(ben);
        bn.configure_sale(address(nft), 1, ben, address(0), 1 ether, bytes32(0));

        vm.startPrank(hacker);
        vm.expectRevert("caller is not the token seller");
        bn.cancel_sale(address(nft), 1);
        vm.stopPrank();

        vm.startPrank(ben);
        vm.expectEmit(true, true, true, false);
        emit SaleCanceled(ben, address(nft), 1);
        bn.cancel_sale(address(nft), 1);
        vm.stopPrank();
        Sale memory sale = bn.get_sale(address(nft), 1);
        assert(sale.seller == address(0));
        assert(sale.payout_receiver == address(0));
        assert(sale.currency_addr == address(0));
        assert(sale.price == 0);
        assert(sale.merkle_root == bytes32(0));
    }

    /// @dev test sale of not configured token
    function test_buy_not_configured_token() public {
        vm.expectRevert("sale not active");
        bn.buy(address(nft), 1, address(this), emptyProof);
    }

    /// @dev test private sale not on allowlist
    function test_buy_not_on_allowlist() public {
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encode(ben, uint256(1)));
        data[1] = keccak256(abi.encode(chris, uint256(3)));
        data[2] = keccak256(abi.encode(david, uint256(4)));
        data[3] = keccak256(abi.encode(bsy, uint256(5)));
        bytes32 root = m.getRoot(data);

        vm.prank(ben);
        bn.configure_sale(address(nft), 1, ben, address(0), 0 ether, root);

        vm.expectRevert("you shall not mint");
        bn.buy(address(nft), 1, address(this), emptyProof);
    }

    /// @dev test sale with invalid royalty info
    function test_buy_invalid_royalty_info() public {
        vm.prank(ben);
        bn.configure_sale(address(nft), 1, ben, address(0), 0 ether, bytes32(0));

        address[] memory recipients = new address[](1);
        recipients[0] = ben;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.05 ether;

        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngine.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        vm.expectRevert("invalid royalty info");
        bn.buy(address(nft), 1, address(this), emptyProof);

        vm.clearMockedCalls();
    }

    /// @dev test sale with reverting royalty lookup
    function test_buy_reverting_royalty() public {
        vm.prank(ben);
        bn.configure_sale(address(nft), 1, ben, address(0), 1 ether, bytes32(0));

        vm.mockCallRevert(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngine.getRoyalty.selector),
            abi.encode("error")
        );

        uint256 prevBalance = ben.balance;
        vm.expectEmit(true, true, true, true);
        emit SaleFulfilled(address(this), address(nft), 1, address(this), Sale(ben, ben, address(0), 1 ether, bytes32(0)));
        bn.buy{value: 1 ether}(address(nft), 1, address(this), emptyProof);
        assert(ben.balance - prevBalance == 1 ether);

        vm.clearMockedCalls();
    }

    /// @dev test sale with reverting eth receiver
    function test_buy_reverting_payout() public {
        address revertingReceiver = address(new RevertingReceiver());

        vm.prank(ben);
        bn.configure_sale(address(nft), 1, revertingReceiver, address(0), 1 ether, bytes32(0));

        vm.expectRevert();
        bn.buy{value: 1 ether}(address(nft), 1, address(this), emptyProof);
    }

    /// @dev test sale with not enough erc20 allowance

    /// @dev test sale with not enough erc20 balance

    /// @dev test sale for 0 eth

    /// @dev test sale with refund

    /// @dev test erc20 sale with refund

    /// @dev test refund with reverting sender

    /// @dev test reentrancy

    /// @dev test private sale with one address

    /// @dev test public sale fuzz

    /// @dev test private sale fuzz

    /// @dev fork test with royalty registry on mainnet

    /// @dev fork test with royalyt registry reverting on mainnet
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Receiver, RevertingReceiver} from "../../utils/Receivers.sol";
import {WETH9} from "../../utils/WETH9.sol";
import {MockERC20, MockERC20WithFee} from "../../utils/MockERC20.sol";
import {RoyaltyPayoutHelperUpgradeable, IRoyaltyEngineV1} from "tl-sol-tools/upgradeable/payments/RoyaltyPayoutHelperUpgradeable.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

contract ExternalRoyaltyPayoutHelper is Initializable, RoyaltyPayoutHelperUpgradeable {

    function initialize(address wethAddress, address royaltyEngineAddress) external initializer {
        __RoyaltyPayoutHelper_init(wethAddress, royaltyEngineAddress);
    }

    function setWethAddress(address wethAddress) external {
        _setWethAddress(wethAddress);
    }

    function setRoyaltyEngineAddress(address royaltyEngineAddress) external {
        _setRoyaltyEngineAddress(royaltyEngineAddress);
    }

    function payoutRoyalties(address token, uint256 tokenId, address currency, uint256 salePrice) external returns(uint256) {
        return _payoutRoyalties(token, tokenId, currency, salePrice);
    }
}

contract TestRoyaltyPayoutHelperUpgradeable is Test {

    using Strings for uint256;

    ExternalRoyaltyPayoutHelper rph;
    address weth;
    address receiver;
    address revertingReceiver;
    MockERC20 erc20;
    MockERC20WithFee erc20fee;

    address royaltyEngine = 0x0385603ab55642cb4Dd5De3aE9e306809991804f;

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);

    function setUp() public {
        weth = address(new WETH9());
        receiver = address(new Receiver());
        revertingReceiver = address(new RevertingReceiver());
        erc20 = new MockERC20(ben);
        erc20fee = new MockERC20WithFee(ben);

        rph = new ExternalRoyaltyPayoutHelper();
        rph.initialize(weth, royaltyEngine);
    }

    function testInit() public view {
        assert(rph.weth() == weth);
        assert(address(rph.royaltyEngine()) == royaltyEngine);
    }
    
    function testInitAgain() public {
        vm.expectRevert();
        rph.initialize(weth, royaltyEngine);
    }

    function testUpdateWethAddress(address newWeth) public {
        rph.setWethAddress(newWeth);
        assert(rph.weth() == newWeth);
    }

    function testUpdateRoyaltyEngine(address newRoyaltyEngine) public {
        rph.setRoyaltyEngineAddress(newRoyaltyEngine);
        assert(address(rph.royaltyEngine()) == newRoyaltyEngine);
    }

    function testPayoutRoyaltiesEOA(uint256 salePrice) public {
        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), salePrice);
        assert(remainingSale == salePrice);
    }

    function testPayoutRoyaltiesRevertingQuery(uint256 salePrice) public {
        vm.mockCallRevert(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            "fail fail"
        );

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), salePrice);
        assert(remainingSale == salePrice);

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesUnequalLengthArrays(uint256 salePrice) public {

        address[] memory recipients = new address[](1);
        recipients[0] = address(1);
        uint256[] memory amounts = new uint256[](0);
        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), salePrice);
        assert(remainingSale == salePrice);

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesZeroLengthArrays(uint256 salePrice) public {

        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), salePrice);
        assert(remainingSale == salePrice);

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesMoreThanSalePrice() public {
        uint256 price = 1 ether;
        address[] memory recipients = new address[](2);
        recipients[0] = address(100);
        recipients[1] = address(101);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.9 ether;
        amounts[1] = 0.2 ether;

        vm.deal(address(rph), price);

        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), price);
        assert(address(100).balance == 0.9 ether);
        assert(remainingSale == 0.1 ether);

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesETH(uint8 numRecipients, uint256 salePrice) public {
        vm.assume(salePrice > 4);
        vm.assume(numRecipients > 0);
        vm.assume(salePrice >= numRecipients);
        uint256 price = salePrice / numRecipients;
        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        uint256 remainingAmount = salePrice;
        for (uint256 i = 0; i < numRecipients; i++) {
            remainingAmount -= price;
            amounts[i] = price;
            recipients[i] = makeAddr(i.toString());
        }

        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        vm.deal(address(rph), salePrice);

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(0), salePrice);
        assert(remainingAmount == remainingSale);
        for (uint256 i = 0; i < numRecipients; i++) {
            assert(recipients[i].balance == price);
        }

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesERC20(uint8 numRecipients, uint256 salePrice) public {
        vm.assume(salePrice > 4);
        vm.assume(numRecipients > 0);
        vm.assume(salePrice >= numRecipients);
        uint256 price = salePrice / numRecipients;
        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        uint256 remainingAmount = salePrice;
        for (uint256 i = 0; i < numRecipients; i++) {
            remainingAmount -= price;
            amounts[i] = price;
            recipients[i] = makeAddr(i.toString());
        }

        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        vm.prank(ben);
        erc20.transfer(address(rph), salePrice);

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(erc20), salePrice);
        assert(remainingAmount == remainingSale);
        for (uint256 i = 0; i < numRecipients; i++) {
            assert(erc20.balanceOf(recipients[i]) == price);
        }

        vm.clearMockedCalls();
    }

    function testPayoutRoyaltiesERC20WithFee(uint8 numRecipients, uint128 salePrice) public {
        vm.assume(salePrice > 4);
        vm.assume(numRecipients > 0);
        vm.assume(salePrice >= numRecipients);
        uint256 price = uint256(salePrice) / numRecipients;
        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        uint256 remainingAmount = salePrice;
        for (uint256 i = 0; i < numRecipients; i++) {
            remainingAmount -= price;
            amounts[i] = price;
            recipients[i] = makeAddr(i.toString());
        }

        vm.mockCall(
            royaltyEngine,
            abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector),
            abi.encode(recipients, amounts)
        );

        vm.prank(ben);
        erc20fee.transfer(address(rph), uint256(salePrice)+1);

        uint256 remainingSale = rph.payoutRoyalties(address(1), 1, address(erc20fee), uint256(salePrice));
        assert(remainingAmount == remainingSale);
        for (uint256 i = 0; i < numRecipients; i++) {
            assert(erc20fee.balanceOf(recipients[i]) == price-1);
        }

        vm.clearMockedCalls();
    }

}
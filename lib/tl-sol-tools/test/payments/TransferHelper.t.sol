// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Receiver, RevertingReceiver} from "../utils/Receivers.sol";
import {WETH9} from "../utils/WETH9.sol";
import {MockERC20, MockERC20WithFee} from "../utils/MockERC20.sol";
import {TransferHelper, ETHTransferFailed, InsufficentERC20Transfer} from "tl-sol-tools/payments/TransferHelper.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

contract ExternalTransferHelper is TransferHelper {

    function safeTransferETH(address recipient, uint256 amount, address weth) external {
        _safeTransferETH(recipient, amount, weth);
    }

    function safeTransferERC20(address recipient, address currency, uint256 amount) external {
        _safeTransferERC20(recipient, currency, amount);
    }

    function safeTransferFromERC20(address sender, address recipient, address currency, uint256 amount) external {
        _safeTransferFromERC20(sender, recipient, currency, amount);
    }
}

contract TestTransferHelper is Test {
    ExternalTransferHelper th;
    address weth;
    address receiver;
    address revertingReceiver;
    MockERC20 erc20;
    MockERC20WithFee erc20fee;

    address ben = address(0x0BEEF);
    address chris = address(0xC0FFEE);
    address david = address(0x1D1B);

    function setUp() public {
        th = new ExternalTransferHelper();
        weth = address(new WETH9());
        receiver = address(new Receiver());
        revertingReceiver = address(new RevertingReceiver());
        erc20 = new MockERC20(ben);
        erc20fee = new MockERC20WithFee(ben);
    }

    function testSafeTransferETH(address recipient, uint256 amount) public {

        vm.assume(
            recipient.code.length == 0 && recipient > address(100)
        );

        // test contract receiver
        vm.deal(address(th), amount);
        uint256 b1 = receiver.balance;
        th.safeTransferETH(receiver, amount, weth);
        assert(receiver.balance - b1 == amount);

        // test recipient
        vm.deal(address(th), amount);
        uint256 b2 = recipient.balance;
        th.safeTransferETH(recipient, amount, weth);
        assert(recipient.balance - b2 == amount);

        // test reverting receiver
        vm.deal(address(th), amount);
        uint256 b3 = IERC20(weth).balanceOf(revertingReceiver);
        th.safeTransferETH(revertingReceiver, amount, weth);
        assert(IERC20(weth).balanceOf(revertingReceiver) - b3 == amount);
    }

    function testSafeTransferERC20(address recipient, uint256 amount) public {

        vm.assume(recipient != address(0) && recipient != address(th) && amount > 0);
        
        // fund contract
        vm.prank(ben);
        erc20.transfer(address(th), amount);

        // test amount with regular ERC20
        uint256 b1 = erc20.balanceOf(recipient);
        th.safeTransferERC20(recipient, address(erc20), amount);
        assert(erc20.balanceOf(recipient) - b1 == amount);

        if (amount > 1) {
            // fund contract
            vm.prank(ben);
            erc20fee.transfer(address(th), amount);

            // test amount with token tax ERC20
            uint256 b2 = erc20fee.balanceOf(recipient);
            th.safeTransferERC20(recipient, address(erc20fee), amount-1);
            assert(erc20fee.balanceOf(recipient) - b2 == amount-2);
        }
    }

    function testSafeTransferFromERC20(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(th) && amount > 0);

        // fund chris
        vm.prank(ben);
        erc20.transfer(chris, amount);

        // test failure for allowance
        vm.expectRevert();
        th.safeTransferFromERC20(chris, recipient, address(erc20), amount);

        // give allowance
        vm.prank(chris);
        erc20.approve(address(th), amount);

        // test amount with regular ERC20
        uint256 b1 = erc20.balanceOf(recipient);
        th.safeTransferFromERC20(chris, recipient, address(erc20), amount);
        assert(erc20.balanceOf(recipient) - b1 == amount);

        if (amount > 1) {
            // fund chris
            vm.prank(ben);
            erc20fee.transfer(chris, amount);

            // test failure for allowance
            vm.expectRevert();
            th.safeTransferFromERC20(chris, recipient, address(erc20fee), amount-1);

            // give allowance
            vm.prank(chris);
            erc20fee.approve(address(th), amount-1);

            // test amount with token tax ERC20
            vm.expectRevert(InsufficentERC20Transfer.selector);
            th.safeTransferFromERC20(chris, recipient, address(erc20fee), amount-1);
        }
    }

}
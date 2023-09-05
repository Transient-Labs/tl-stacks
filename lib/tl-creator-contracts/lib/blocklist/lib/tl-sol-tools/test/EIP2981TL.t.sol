// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {MockEIP2981TL} from "./mocks/MockEIP2981TL.sol";
import {ZeroAddressError, MaxRoyaltyError} from "../src/royalties/EIP2981TL.sol";

contract TestEIP2981TL is Test {
    MockEIP2981TL public mockContract;

    ///////////////////// GENERAL TESTS /////////////////////
    function testDefaultRoyaltyInfo(uint256 tokenId, address recipient, uint16 percentage) public {
        if (recipient == address(0)) {
            vm.expectRevert(ZeroAddressError.selector);
        } else if (percentage > 10_000) {
            vm.expectRevert(MaxRoyaltyError.selector);
        }
        mockContract = new MockEIP2981TL(recipient, uint256(percentage));
        if (recipient != address(0) && percentage <= 10_000) {
            (address returnedRecipient, uint256 amount) = mockContract.royaltyInfo(tokenId, 10000);
            assertEq(recipient, returnedRecipient);
            assertEq(amount, percentage);
        }
    }

    function testERC165Support(address recipient, uint16 percentage) public {
        if (recipient != address(0) && percentage <= 10_000) {
            mockContract = new MockEIP2981TL(recipient, uint256(percentage));
            assertTrue(mockContract.supportsInterface(0x01ffc9a7)); // ERC165 interface id
            assertTrue(mockContract.supportsInterface(0x2a55205a)); // EIP2981 interface id
        }
    }

    ///////////////////// DEFAULT OVERRIDE TEST /////////////////////
    function testOverrideDefaultRoyaltyInfo(uint256 tokenId, address recipient, uint16 percentage) public {
        address defaultRecipient = makeAddr("account");
        mockContract = new MockEIP2981TL(defaultRecipient, 10_000);
        if (recipient == address(0)) {
            vm.expectRevert(ZeroAddressError.selector);
        } else if (percentage > 10_000) {
            vm.expectRevert(MaxRoyaltyError.selector);
        }
        mockContract.setDefaultRoyalty(recipient, uint256(percentage));
        if (recipient != address(0) && percentage <= 10_000) {
            (address returnedRecipient, uint256 amount) = mockContract.royaltyInfo(tokenId, 10000);
            assertEq(recipient, returnedRecipient);
            assertEq(amount, percentage);
        }
    }

    ///////////////////// TOKEN OVERRIDE TEST /////////////////////
    function testOverrideTokenRoyaltyInfo(uint256 tokenId, address recipient, uint16 percentage) public {
        address defaultRecipient = makeAddr("account");
        mockContract = new MockEIP2981TL(defaultRecipient, 10_000);
        if (recipient == address(0)) {
            vm.expectRevert(ZeroAddressError.selector);
        } else if (percentage > 10_000) {
            vm.expectRevert(MaxRoyaltyError.selector);
        }
        mockContract.setTokenRoyalty(tokenId, recipient, uint256(percentage));
        if (recipient != address(0) && percentage <= 10_000) {
            (address returnedRecipient, uint256 amount) = mockContract.royaltyInfo(tokenId, 10000);
            assertEq(recipient, returnedRecipient);
            assertEq(amount, percentage);
        }
    }
}

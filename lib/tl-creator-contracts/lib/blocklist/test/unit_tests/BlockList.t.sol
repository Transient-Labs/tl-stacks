// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Unauthorized, BlockedOperator} from "../../src/IBlockList.sol";
import {IBlockListRegistry} from "../../src/IBlockListRegistry.sol";
import {BlockListMock} from "../mocks/BlockListMock.sol";
import {FakeBlockList} from "../mocks/FakeBlockList.sol";

contract BlockListUnitTest is Test {
    event BlockListRegistryUpdated(address indexed caller, address indexed oldRegistry, address indexed newRegistry);

    BlockListMock public mockContract;

    function setUp() public {
        mockContract = new BlockListMock(address(0));
        mockContract.mint();
    }

    function testInitialization() public {
        assertTrue(mockContract.isBlockListAdmin(address(this)));
        assertEq(address(mockContract.blockListRegistry()), address(0));
    }

    /// @dev test to ensure the try/catch works as intended on EOA registries
    function testZeroAddressRegistry(address operator) public {
        assertFalse(mockContract.getBlockListStatus(operator));
    }

    /// @dev test to ensure the try/catch works as intended with bad contract registries
    function testFakeRegistry(address operator) public {
        address registry = address(new FakeBlockList());
        mockContract.updateBlockListRegistry(registry);
        assertFalse(mockContract.getBlockListStatus(operator));
    }

    /// @dev test to update the registry
    function testUpdateBlockListRegistry(address newRegistry) public {
        address oldRegistry = address(mockContract.blockListRegistry());
        vm.expectEmit(true, true, true, false);
        emit BlockListRegistryUpdated(address(this), oldRegistry, newRegistry);
        mockContract.updateBlockListRegistry(newRegistry);
    }

    /// @dev test access control
    function testAccessControl(address user) public {
        vm.assume(user != address(this));
        vm.startPrank(user, user);
        vm.expectRevert(Unauthorized.selector);
        mockContract.updateBlockListRegistry(address(0));
        vm.stopPrank();
    }

    /// @dev test approve fail
    function testApproveFail() public {
        address registry = makeAddr("Registry");
        mockContract.updateBlockListRegistry(registry);
        vm.mockCall(registry, abi.encodeWithSelector(IBlockListRegistry.getBlockListStatus.selector), abi.encode(true));
        vm.expectRevert(BlockedOperator.selector);
        mockContract.approve(registry, 1);
        vm.clearMockedCalls();
    }

    /// @dev test approve succeed
    function testApproveSucceed() public {
        address registry = makeAddr("Registry");
        mockContract.updateBlockListRegistry(registry);
        vm.mockCall(registry, abi.encodeWithSelector(IBlockListRegistry.getBlockListStatus.selector), abi.encode(false));
        mockContract.approve(registry, 1);
        assertEq(mockContract.getApproved(1), registry);
        vm.clearMockedCalls();
    }

    /// @dev test set approval for all fail
    function testSetApprovalForAllFail() public {
        address registry = makeAddr("Registry");
        mockContract.updateBlockListRegistry(registry);
        vm.mockCall(registry, abi.encodeWithSelector(IBlockListRegistry.getBlockListStatus.selector), abi.encode(true));
        vm.expectRevert(BlockedOperator.selector);
        mockContract.setApprovalForAll(registry, true);
        vm.clearMockedCalls();
    }

    /// @dev test set approval for all succeed
    function testSetApprovalForAllSucceed() public {
        address registry = makeAddr("Registry");
        mockContract.updateBlockListRegistry(registry);
        vm.mockCall(registry, abi.encodeWithSelector(IBlockListRegistry.getBlockListStatus.selector), abi.encode(false));
        mockContract.setApprovalForAll(registry, true);
        assertTrue(mockContract.isApprovedForAll(address(this), registry));
        vm.clearMockedCalls();
    }
}

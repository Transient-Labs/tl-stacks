// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {BlockedOperator} from "../../src/IBlockList.sol";
import {BlockListRegistryFactory} from "../../src/BlockListRegistryFactory.sol";
import {BlockListRegistry, IBlockListRegistry} from "../../src/BlockListRegistry.sol";
import {BlockListMockUpgradeable} from "../mocks/BlockListMockUpgradeable.sol";

contract BlockListUpgradeableIntegrationTest is Test {
    address public blockListRegistryTemplate;
    address public registry;
    BlockListRegistryFactory public factory;
    BlockListMockUpgradeable public mockContract;
    address[] public blockList;

    function setUp() public {
        blockList.push(address(1));
        blockList.push(address(2));
        blockList.push(address(3));

        blockListRegistryTemplate = address(new BlockListRegistry(true));
        factory = new BlockListRegistryFactory(blockListRegistryTemplate);
        registry = factory.createBlockListRegistry(blockList);
        mockContract = new BlockListMockUpgradeable();
        mockContract.initialize(registry);
    }

    // Test Initialization
    function testInitialization() public {
        assertTrue(mockContract.getBlockListStatus(address(1)));
        assertTrue(mockContract.getBlockListStatus(address(2)));
        assertTrue(mockContract.getBlockListStatus(address(3)));
        assertFalse(mockContract.getBlockListStatus(address(4)));
    }

    // Test Add & Remove Blocked Operators
    function testAddRemoveOperators() public {
        address[] memory newOperators = new address[](4);
        newOperators[0] = address(4);
        newOperators[1] = address(5);
        newOperators[2] = address(6);
        newOperators[3] = address(7);

        // add operators
        BlockListRegistry(registry).setBlockListStatus(newOperators, true);
        assertTrue(mockContract.getBlockListStatus(address(4)));
        assertTrue(mockContract.getBlockListStatus(address(5)));
        assertTrue(mockContract.getBlockListStatus(address(6)));
        assertTrue(mockContract.getBlockListStatus(address(7)));

        for (uint256 i = 0; i < newOperators.length; i++) {
            vm.expectRevert(BlockedOperator.selector);
            mockContract.setApprovalForAll(newOperators[i], true);
        }

        // remove operators
        BlockListRegistry(registry).setBlockListStatus(newOperators, false);
        assertFalse(mockContract.getBlockListStatus(address(4)));
        assertFalse(mockContract.getBlockListStatus(address(5)));
        assertFalse(mockContract.getBlockListStatus(address(6)));
        assertFalse(mockContract.getBlockListStatus(address(7)));

        for (uint256 i = 0; i < newOperators.length; i++) {
            mockContract.setApprovalForAll(newOperators[i], true);
            assertTrue(mockContract.isApprovedForAll(address(this), newOperators[i]));
        }
    }

    // Test New Registry
    function testNewRegistry(address[] calldata blockedOperators) public {
        address newRegistry = address(factory.createBlockListRegistry(blockedOperators));
        mockContract.updateBlockListRegistry(newRegistry);
        for (uint256 i = 0; i < blockedOperators.length; i++) {
            vm.expectRevert(BlockedOperator.selector);
            mockContract.setApprovalForAll(blockedOperators[i], true);
        }
    }
}

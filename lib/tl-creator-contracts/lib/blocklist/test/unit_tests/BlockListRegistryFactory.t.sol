// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {BlockListRegistryFactory} from "../../src/BlockListRegistryFactory.sol";

contract BlockListRegistryFactoryUnitTest is Test {
    BlockListRegistryFactory public factory;

    event BlockListRegistryCreated(address indexed creator, address indexed template, address indexed registryAddress);

    function setUp() public {
        factory = new BlockListRegistryFactory(address(1));
    }

    // Initialization Tests
    function testInitialization() public {
        assertEq(factory.owner(), address(this));
        assertEq(factory.blockListRegistryTemplate(), address(1));
    }

    // Access Control Tests
    function testAccessControl(address user) public {
        vm.assume(user != address(this));
        vm.startPrank(user, user);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setBlockListRegistryTemplate(address(2));
        vm.stopPrank();
    }

    // Create Registry Tests
    function testCreateRegistry(address user, address[] calldata initBlockList) public {
        vm.startPrank(user, user);
        vm.expectEmit(true, true, false, false); // can't necessarily predict clone address
        emit BlockListRegistryCreated(user, factory.blockListRegistryTemplate(), address(2));
        factory.createBlockListRegistry(initBlockList);
        vm.stopPrank();
    }
}

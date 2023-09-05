// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {NotRoleOrOwner} from "tl-sol-tools/access/OwnableAccessControl.sol";
import {BlockListRegistry, IBlockListRegistry} from "../../src/BlockListRegistry.sol";
import {IERC165Upgradeable} from "openzeppelin-upgradeable/utils/introspection/IERC165Upgradeable.sol";

contract BlockListRegistryUnitTest is Test, BlockListRegistry {
    address[] public initBlockedOperators = [address(1), address(2), address(3)];
    bytes32 public constant NOT_ADMIN_ROLE = keccak256("NOT_ADMIN_ROLE");
    BlockListRegistry public blocklist;

    constructor() BlockListRegistry(false) {}

    function setUp() public {
        blocklist = new BlockListRegistry(false);
        blocklist.initialize(address(this), initBlockedOperators);
    }

    function testInitialization() public {
        assertEq(blocklist.owner(), address(this));
        assertTrue(blocklist.getBlockListStatus(address(1)));
        assertTrue(blocklist.getBlockListStatus(address(2)));
        assertTrue(blocklist.getBlockListStatus(address(3)));
        assertFalse(blocklist.getBlockListStatus(address(4)));
    }

    function testClearBlockList() public {
        vm.expectEmit({checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: false});
        emit BlockListCleared(address(this));
        blocklist.clearBlockList();

        assertFalse(blocklist.getBlockListStatus(address(1)));
        assertFalse(blocklist.getBlockListStatus(address(2)));
        assertFalse(blocklist.getBlockListStatus(address(3)));
        assertFalse(blocklist.getBlockListStatus(address(4)));
    }

    function testSupportsInterface() public {
        assertTrue(blocklist.supportsInterface(type(IBlockListRegistry).interfaceId));
        assertTrue(blocklist.supportsInterface(type(IERC165Upgradeable).interfaceId));
    }

    function testSetBlockListStatus() public {
        address[] memory operators = new address[](10);
        operators[0] = address(10);
        operators[1] = address(11);
        operators[2] = address(12);
        operators[3] = address(13);
        operators[4] = address(14);
        operators[5] = address(15);
        operators[6] = address(16);
        operators[7] = address(17);
        operators[8] = address(18);
        operators[9] = address(19);

        // set operators blocked
        for (uint256 i = 0; i < operators.length; i++) {
            vm.expectEmit({checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: false});
            emit BlockListStatusChange(address(this), operators[i], true);
        }
        blocklist.setBlockListStatus(operators, true);

        // set operators not blocked
        for (uint256 i = 0; i < operators.length; i++) {
            vm.expectEmit({checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: false});
            emit BlockListStatusChange(address(this), operators[i], false);
        }
        blocklist.setBlockListStatus(operators, false);
    }

    function testAccessControl(address user) public {
        // set admins for testing
        address[] memory admins = new address[](3);
        admins[0] = makeAddr("account1");
        admins[1] = makeAddr("account2");
        admins[2] = makeAddr("account3");
        blocklist.setRole(BLOCK_LIST_ADMIN_ROLE, admins, true);

        // set blocked operators
        address[] memory operators = new address[](10);
        operators[0] = address(10);
        operators[1] = address(11);
        operators[2] = address(12);
        operators[3] = address(13);
        operators[4] = address(14);
        operators[5] = address(15);
        operators[6] = address(16);
        operators[7] = address(17);
        operators[8] = address(18);
        operators[9] = address(19);

        // test user actions
        vm.startPrank(user, user);
        if (user == admins[0] || user == admins[1] || user == admins[2] || user == address(this)) {
            // add blocklist operators
            for (uint256 i = 0; i < operators.length; i++) {
                vm.expectEmit({checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: false});
                emit BlockListStatusChange(user, operators[i], true);
            }
            blocklist.setBlockListStatus(operators, true);

            // clear blocklist
            blocklist.clearBlockList();
        } else {
            // add blocklist operators
            vm.expectRevert(abi.encodeWithSelector(NotRoleOrOwner.selector, BLOCK_LIST_ADMIN_ROLE));
            blocklist.setBlockListStatus(operators, true);

            // clear blocklist
            vm.expectRevert(abi.encodeWithSelector(NotRoleOrOwner.selector, BLOCK_LIST_ADMIN_ROLE));
            blocklist.clearBlockList();
        }
        vm.stopPrank();

        // clear admins as cleanup
        blocklist.setRole(BLOCK_LIST_ADMIN_ROLE, admins, false);
    }
}

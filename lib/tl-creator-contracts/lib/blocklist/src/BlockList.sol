// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {BlockedOperator, Unauthorized, IBlockList} from "./IBlockList.sol";
import {IBlockListRegistry} from "./IBlockListRegistry.sol";

/// @title BlockList
/// @author transientlabs.xyz
/// @notice abstract contract that can be inherited to block
///         approvals from non-royalty paying marketplaces
/// @custom:version 4.0.0
abstract contract BlockList is IBlockList {
    /*//////////////////////////////////////////////////////////////////////////
                                Public State Variables
    //////////////////////////////////////////////////////////////////////////*/

    IBlockListRegistry public blockListRegistry;

    /*//////////////////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////////////////*/

    event BlockListRegistryUpdated(address indexed caller, address indexed oldRegistry, address indexed newRegistry);

    /*//////////////////////////////////////////////////////////////////////////
                                Modifiers
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev modifier that can be applied to approval functions in order to block listings on marketplaces
    modifier notBlocked(address operator) {
        if (getBlockListStatus(operator)) {
            revert BlockedOperator();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    /// @param blockListRegistryAddr - the initial BlockList Registry Address
    constructor(address blockListRegistryAddr) {
        blockListRegistry = IBlockListRegistry(blockListRegistryAddr);
        emit BlockListRegistryUpdated(msg.sender, address(0), blockListRegistryAddr);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Admin Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice function to transfer ownership of the blockList
    /// @dev requires blockList admin
    /// @dev can be transferred to the ZERO_ADDRESS if desired
    /// @dev BE VERY CAREFUL USING THIS
    /// @param newBlockListRegistry - the address of the new BlockList registry
    function updateBlockListRegistry(address newBlockListRegistry) public {
        if (!isBlockListAdmin(msg.sender)) revert Unauthorized();

        address oldRegistry = address(blockListRegistry);
        blockListRegistry = IBlockListRegistry(newBlockListRegistry);
        emit BlockListRegistryUpdated(msg.sender, oldRegistry, newBlockListRegistry);
    }

    /*//////////////////////////////////////////////////////////////////////////
                          Public Read Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlockList
    function getBlockListStatus(address operator) public view override returns (bool) {
        if (address(blockListRegistry).code.length == 0) return false;
        try blockListRegistry.getBlockListStatus(operator) returns (bool isBlocked) {
            return isBlocked;
        } catch {
            return false;
        }
    }

    /// @notice Abstract function to determine if an address is a blocklist admin.
    /// @param potentialAdmin - the potential admin address to check
    function isBlockListAdmin(address potentialAdmin) public view virtual returns (bool);
}

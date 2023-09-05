// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {OwnableAccessControl} from "../../src/access/OwnableAccessControl.sol";

contract MockOwnableAccessControl is OwnableAccessControl {
    uint256 public number;
    bytes32 public ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public MINTER_ROLE = keccak256("MINTER");

    constructor() OwnableAccessControl() {}

    /// @dev function to let admins give minter roles
    function setMinterRole(address minter) external onlyRoleOrOwner(ADMIN_ROLE) {
        address[] memory minters = new address[](1);
        minters[0] = minter;
        _setRole(MINTER_ROLE, minters, true);
    }

    /// @dev function restricted to only owner
    function onlyOwnerFunction(uint256 newNumber) external onlyOwner {
        number = newNumber;
    }

    /// @dev function restricted to admin or owner
    function onlyAdminOrOwnerFunction(uint256 newNumber) external onlyRoleOrOwner(ADMIN_ROLE) {
        number = newNumber;
    }

    /// @dev function restricted only to admin role
    function onlyAdminFunction(uint256 newNumber) external onlyRole(ADMIN_ROLE) {
        number = newNumber;
    }

    /// @dev function restritued to only minter role
    function onlyMinterFunction(uint256 newNumber) external onlyRole(MINTER_ROLE) {
        number = newNumber;
    }
}

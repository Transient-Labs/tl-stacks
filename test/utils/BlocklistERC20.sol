// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

/// @dev ERC-20 that reverts on transfers to blocked addresses (similar to USDC's blacklist)
contract BlocklistERC20 is ERC20 {
    mapping(address => bool) public blocked;

    constructor(address mintReceiver) ERC20("Blocklist Token", "BLOCK") {
        _mint(mintReceiver, type(uint256).max);
    }

    function setBlocked(address account, bool status) external {
        blocked[account] = status;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[to], "blocked");
        super._update(from, to, value);
    }
}

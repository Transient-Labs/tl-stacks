// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

/// @dev ERC-20 that burns 1% of every transfer, so recipients receive less than the amount sent
contract FeeOnTransferERC20 is ERC20 {
    constructor(address mintReceiver) ERC20("Fee Token", "FEE") {
        _mint(mintReceiver, 1_000_000 ether);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = value / 100;
        super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}

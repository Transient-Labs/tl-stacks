// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(address mintReceiver) ERC20("Test Token", "TEST") {
        _mint(mintReceiver, type(uint256).max);
    }
}

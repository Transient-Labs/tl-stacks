// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(address mintReceiver) ERC20("Test Token", "TEST") {
        _mint(mintReceiver, type(uint256).max);
    }
}

contract MockERC20WithFee is ERC20 {
    constructor(address mintReceiver) ERC20("Test Token", "TEST") {
        _mint(mintReceiver, type(uint256).max);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        _burn(owner, 1);
        _transfer(owner, to, value-1);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _burn(from, 1);
        _transfer(from, to, value-1);
        return true;
    }
}
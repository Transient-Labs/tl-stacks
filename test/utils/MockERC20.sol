// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(address mintReceiver) ERC20("Test Token", "TEST") {
        _mint(mintReceiver, type(uint256).max);
    }
}

/// @dev Test token whose direct transfers can return false before, after, or partway through moving funds.
///      `transferFrom` remains standard so the auction house can escrow a fully funded bid or purchase.
contract FalseReturnERC20 is ERC20 {
    enum Mode {
        NORMAL,
        NO_TRANSFER_FALSE,
        FULL_TRANSFER_FALSE,
        PARTIAL_TRANSFER_FALSE
    }

    Mode public mode;
    bool public balanceQueriesDisabled;

    constructor(address mintReceiver) ERC20("False Return Token", "FALSE") {
        _mint(mintReceiver, type(uint256).max);
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function setBalanceQueriesDisabled(bool disabled) external {
        balanceQueriesDisabled = disabled;
    }

    function balanceOf(address account) public view override returns (uint256) {
        require(!balanceQueriesDisabled, "balance disabled");
        return super.balanceOf(account);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (mode == Mode.NO_TRANSFER_FALSE) return false;
        if (mode == Mode.FULL_TRANSFER_FALSE) {
            super.transfer(to, value);
            return false;
        }
        if (mode == Mode.PARTIAL_TRANSFER_FALSE) {
            super.transfer(to, value / 2);
            return false;
        }
        return super.transfer(to, value);
    }
}

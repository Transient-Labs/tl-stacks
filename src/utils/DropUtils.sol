// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

library DropPhase {
    uint256 constant NOT_CONFIGURED = 1;
    uint256 constant BEFORE_SALE = 2;
    uint256 constant PRESALE = 4;
    uint256 constant PUBLIC_SALE = 8;
    uint256 constant ENDED = 16;
}

library DropParam {
    uint256 constant MERKLE_ROOT = 1;
    uint256 constant ALLOWANCE = 2;
    uint256 constant COST = 4;
    uint256 constant DURATION = 8;
    uint256 constant PAYOUT_ADDRESS = 16;
}
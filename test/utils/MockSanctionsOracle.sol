// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IChainalysisSanctionsOracle} from "src/lib/IChainalysisSanctionsOracle.sol";

/// @dev Sanctions oracle whose flags can be flipped per address, so stateful tests can sanction and clear accounts
contract MockSanctionsOracle is IChainalysisSanctionsOracle {
    mapping(address => bool) public sanctioned;

    function setSanctioned(address account, bool status) external {
        sanctioned[account] = status;
    }

    function isSanctioned(address account) external view returns (bool) {
        return sanctioned[account];
    }
}

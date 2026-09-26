// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IChainalysisSanctionsOracle} from "./IChainalysisSanctionsOracle.sol";

/// @title Sanctions Compliance
/// @notice Abstract contract to comply with U.S. sanctioned addresses
/// @dev Uses the Chainalysis Sanctions Oracle for checking sanctions
/// @author Transient Labs, Inc.
contract SanctionsCompliance {
    /////////////////////////////////////////////////////////////////////
    // STORAGE
    /////////////////////////////////////////////////////////////////////

    IChainalysisSanctionsOracle public oracle;

    /////////////////////////////////////////////////////////////////////
    // ERRORS
    /////////////////////////////////////////////////////////////////////

    /// @dev Sanctioned address by OFAC
    error SanctionedAddress();

    /////////////////////////////////////////////////////////////////////
    // EVENTS
    /////////////////////////////////////////////////////////////////////

    event SanctionsOracleUpdated(address indexed prevOracle, address indexed newOracle);

    /////////////////////////////////////////////////////////////////////
    // CONSTRUCTOR
    /////////////////////////////////////////////////////////////////////

    constructor(address initOracle) {
        _updateSanctionsOracle(initOracle);
    }

    /////////////////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Internal function to change the sanctions oracle
    /// @param newOracle The new sanctions oracle address
    function _updateSanctionsOracle(address newOracle) internal {
        address prevOracle = address(oracle);
        oracle = IChainalysisSanctionsOracle(newOracle);

        emit SanctionsOracleUpdated(prevOracle, newOracle);
    }

    /// @notice Internal function to check the sanctions oracle for an address
    /// @dev Disable sanction checking by setting the oracle to the zero address
    /// @param account The address to check
    /// @return bool Boolean indicating if the address is sanctioned
    function _isSanctioned(address account) internal view returns (bool) {
        if (address(oracle) == address(0)) return false;
        return oracle.isSanctioned(account);
    }
}

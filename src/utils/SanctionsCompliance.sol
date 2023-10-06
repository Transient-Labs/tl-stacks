// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CommonErrors, ChainalysisSanctionsOracle} from "./CommonUtils.sol";

/*//////////////////////////////////////////////////////////////////////////
                            SanctionsCompliance
//////////////////////////////////////////////////////////////////////////*/

/// @title Sanctions Compliance
/// @notice Abstract contract to comply with U.S. sanctions
/// @dev Uses the Chainalysis Sanctions Oracle for checking sanctions
contract SanctionsCompliance is CommonErrors {
    /*//////////////////////////////////////////////////////////////////////////
                                State Variables
    //////////////////////////////////////////////////////////////////////////*/

    ChainalysisSanctionsOracle public oracle;

    /*//////////////////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////////////////*/

    event SanctionsOracleUpdated(address indexed prevOracle, address indexed newOracle);

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address initOracle) {
        _updateSanctionsOracle(initOracle);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Internal Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal function to change the sanctions oracle
    /// @param newOracle The new sanctions oracle address
    function _updateSanctionsOracle(address newOracle) internal {
        address prevOracle = address(oracle);
        oracle = ChainalysisSanctionsOracle(newOracle);

        emit SanctionsOracleUpdated(prevOracle, newOracle);
    }

    /// @notice Internal function to check the sanctions oracle for an address
    /// @dev Reverts if sanctioned
    /// @dev Disable sanction checking by setting the oracle to the zero address
    /// @param sender The address that is trying to send money
    function _isNotSanctioned(address sender) internal view {
        if (address(oracle) != address(0)) {
            if (oracle.isSanctioned(sender)) revert SanctionedAddress();
        }
    }
}

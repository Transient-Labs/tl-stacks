// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Currency Allowlist
/// @notice Abstract contract to restrict sales to vetted ERC-20 currencies
/// @dev Native currency (the zero address) is always allowed
/// @author Transient Labs, Inc.
abstract contract CurrencyAllowlist {
    /////////////////////////////////////////////////////////////////////
    // STORAGE
    /////////////////////////////////////////////////////////////////////

    mapping(address => bool) public allowedCurrencies;

    /////////////////////////////////////////////////////////////////////
    // ERRORS
    /////////////////////////////////////////////////////////////////////

    /// @dev Currency is not on the allowlist
    error CurrencyNotAllowed();

    /////////////////////////////////////////////////////////////////////
    // EVENTS
    /////////////////////////////////////////////////////////////////////

    event CurrencyAllowlistUpdated(address indexed currencyAddress, bool indexed allowed);

    /////////////////////////////////////////////////////////////////////
    // INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Internal function to add or remove a currency from the allowlist
    /// @dev Removing a currency only blocks new sales from using it, existing sales are unaffected
    /// @param currencyAddress The ERC-20 currency address
    /// @param allowed Boolean indicating if the currency is allowed
    function _setCurrencyAllowed(address currencyAddress, bool allowed) internal {
        allowedCurrencies[currencyAddress] = allowed;

        emit CurrencyAllowlistUpdated(currencyAddress, allowed);
    }

    /// @notice Internal function to check if a currency is allowed
    /// @param currencyAddress The currency address (zero address represents native currency)
    /// @return bool Boolean indicating if the currency is allowed
    function _isCurrencyAllowed(address currencyAddress) internal view returns (bool) {
        return currencyAddress == address(0) || allowedCurrencies[currencyAddress];
    }
}

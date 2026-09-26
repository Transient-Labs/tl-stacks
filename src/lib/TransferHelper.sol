// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";

/// @title Transfer Helper
/// @notice Abstract contract that has helper function for sending ETH and ERC20's safely
/// @author Transient Labs, Inc.
abstract contract TransferHelper {
    /////////////////////////////////////////////////////////////////////
    // TYPES
    /////////////////////////////////////////////////////////////////////

    using SafeERC20 for IERC20;

    /////////////////////////////////////////////////////////////////////
    // ERRORS
    /////////////////////////////////////////////////////////////////////

    /// @dev ETH transfer failed
    error ETHTransferFailed();

    /// @dev Transferred too few ERC-20 tokens
    error InsufficentERC20Transfer();

    /////////////////////////////////////////////////////////////////////
    // ETH FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to transfer ETH, forwarding all gas
    /// @dev Reverts on failure to send the ETH
    /// @dev If the `amount` is zero, the function returns in order to save gas
    /// @param recipient The recipient of the ETH
    /// @param amount The amount of ETH to send
    function _safeTransferETH(address recipient, uint256 amount) internal {
        if (amount == 0) return;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    /// @notice Function to attempt to transfer ETH, with a gas limit
    /// @dev Does not revert on failure, instead returns a boolean indicating success
    /// @dev Callers should skip zero amounts themselves
    /// @param recipient The recipient of the ETH
    /// @param amount The amount of ETH to send
    /// @param gasLimit The gas to forward
    /// @return success Boolean indicating if the transfer succeeded
    function _trySafeTransferETH(address recipient, uint256 amount, uint256 gasLimit) internal returns (bool success) {
        (success,) = recipient.call{value: amount, gas: gasLimit}("");
    }

    /////////////////////////////////////////////////////////////////////
    // ERC-20 FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to safely transfer ERC-20 tokens from the contract, without checking for token tax
    /// @dev Does not check if the sender has enough balance as that is handled by the token contract
    /// @dev Does not check for token tax as that could lock up funds in the contract
    /// @dev Reverts on failure to transfer
    /// @dev If the `amount` is zero, the function returns in order to save gas
    /// @param recipient The recipient of the ERC-20 token
    /// @param currency The address of the ERC-20 token
    /// @param amount The amount of ERC-20 to send
    function _safeTransferERC20(address recipient, address currency, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(currency).safeTransfer(recipient, amount);
    }

    /// @notice Function to attempt to transfer ERC-20 tokens from the contract, without checking for token tax
    /// @dev Does not revert on failure, instead returns a boolean indicating success
    /// @dev Callers should skip zero amounts themselves
    /// @param recipient The recipient of the ERC-20 token
    /// @param currency The address of the ERC-20 token
    /// @param amount The amount of ERC-20 to send
    /// @return success Boolean indicating if the transfer succeeded
    function _trySafeTransferERC20(address recipient, address currency, uint256 amount)
        internal
        returns (bool success)
    {
        return IERC20(currency).trySafeTransfer(recipient, amount);
    }

    /// @notice Function to safely transfer ERC-20 tokens from another address to a recipient
    /// @dev Does not check if the sender has enough balance or allowance for this contract as that is handled by the token contract
    /// @dev Reverts on failure to transfer
    /// @dev Reverts if there is a token tax taken out
    /// @dev Returns and doesn't do anything if the sender and recipient are the same address
    /// @dev If the `amount` is zero, the function returns in order to save gas
    /// @param sender The sender of the tokens
    /// @param recipient The recipient of the ERC-20 token
    /// @param currency The address of the ERC-20 token
    /// @param amount The amount of ERC-20 to send
    function _safeTransferFromERC20(address sender, address recipient, address currency, uint256 amount) internal {
        if (amount == 0) return;
        if (sender == recipient) return;
        IERC20 token = IERC20(currency);
        uint256 intialBalance = token.balanceOf(recipient);
        token.safeTransferFrom(sender, recipient, amount);
        uint256 finalBalance = token.balanceOf(recipient);
        if (finalBalance - intialBalance < amount) revert InsufficentERC20Transfer();
    }
}

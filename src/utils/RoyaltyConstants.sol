// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @dev Constants shared by royalty schedule selection and payout.
library RoyaltyConstants {
    /// @dev Maximum number of positional royalty recipients considered by the auction house.
    uint256 internal constant MAX_ROYALTY_RECIPIENTS = 10;
}

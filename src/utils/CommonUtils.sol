// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/// @dev Enum to encapsulate drop phases
enum DropPhase {
    NOT_CONFIGURED,
    NOT_STARTED,
    PRESALE,
    PUBLIC_SALE,
    ENDED
}

/// @dev Enum to encapsulate drop types
enum DropType {
    NOT_CONFIGURED,
    REGULAR,
    VELOCITY
}

/// @dev Errors for Drops
interface DropErrors {
    error NotDropAdmin();
    error NotApprovedMintContract();
    error InvalidPayoutReceiver();
    error InvalidDropSupply();
    error DropAlreadyConfigured();
    error DropUpdateNotAllowed();
    error InvalidDropType();
    error NotAllowedForVelocityDrops();
    error MintZeroTokens();
    error NotOnAllowlist();
    error YouShallNotMint();
    error AlreadyReachedMintAllowance();
    error CannotMintMoreThanAllowed();
    error IncorrectFunds();
    error ProtocolFeeSplitsTooLarge();
}

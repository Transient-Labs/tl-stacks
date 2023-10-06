// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

/// @dev Common Errors
interface CommonErrors {
    error SanctionOracleError();
    error SanctionedAddress();
}

/// @dev Errors for Drops
interface DropErrors is CommonErrors {
    error NotDropAdmin();
    error NotApprovedMintContract();
    error InvalidPayoutReceiver();
    error InvalidDropSupply();
    error DropNotConfigured();
    error DropAlreadyConfigured();
    error InvalidDropType();
    error NotAllowedForVelocityDrops();
    error MintZeroTokens();
    error NotOnAllowlist();
    error YouShallNotMint();
    error AlreadyReachedMintAllowance();
    error InvalidBatchArguments();
    error InsufficientFunds();
}

/// @dev Errors for the Auction House
interface AuctionHouseErrors is CommonErrors {
    error PercentageTooLarge();
    error CallerNotTokenOwner();
    error AuctionHouseNotApproved();
    error PayoutToZeroAddress();
    error NftNotOwnedBySeller();
    error NftNotTransferred();
    error AuctionNotConfigured();
    error AuctionNotStarted();
    error AuctionStarted();
    error AuctionNotOpen();
    error BidTooLow();
    error AuctionEnded();
    error AuctionNotEnded();
    error InsufficientMsgValue();
    error SaleNotConfigured();
    error SaleNotOpen();
}

interface ChainalysisSanctionsOracle {
    function isSanctioned(address addr) external view returns (bool);
}

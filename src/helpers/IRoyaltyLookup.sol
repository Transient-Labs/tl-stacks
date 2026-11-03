// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IRoyaltyLookup.sol
/// @notice Interface for royalty lookup helper contracts that help the TLAuctionHouse determine the royalty to pay
/// @author Transient Labs, Inc.
interface IRoyaltyLookup {
    /// @notice Function to lookup the creator address for a given token
    /// @dev Should attempt to use the royalty registry under the hood where possible
    function getRoyalty(address nftAddress, uint256 tokenId, uint256 value)
        external
        returns (address payable[] memory recipients, uint256[] memory amounts);

    /// @notice Function to look up royalties for a given token in a read-only context
    /// @dev Should attempt to use the royalty registry under the hood where possible. Integrations previewing an
    ///      auction-house payout should call `TLAuctionHouse.getRoyalty`; a direct `eth_call` to this function must
    ///      set `from` to the auction-house address so caller-dependent recipient filtering matches settlement.
    function getRoyaltyView(address nftAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory recipients, uint256[] memory amounts);
}

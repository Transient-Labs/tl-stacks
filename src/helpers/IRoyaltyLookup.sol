// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/// @title IRoyaltyLookup.sol
/// @notice Interface for royalty lookup helper contracts that help the TLAuctionHouse determine the royalty to pay
/// @author transientlabs.xyz
interface IRoyaltyLookup {
    /// @notice Function to lookup the creator address for a given token
    /// @dev Should attempt to use the royalty registry under the hood where possible
    function getRoyalty(address nftAddress, uint256 tokenId, uint256 value)
        external
        returns (address payable[] memory recipients, uint256[] memory amounts);

    /// @notice Funciton to lookup the creator address for a given token, but only in a read-only view
    /// @dev Should attempt to use the royalty registry under the hood where possible
    function getRoyaltyView(address nftAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory recipients, uint256[] memory amounts);
}

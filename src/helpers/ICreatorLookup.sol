// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/// @title ICreatorLookup.sol
/// @notice Interface for the creator lookup helper contracts that help the TLAuctionHouse determine a primary from secondary sale
/// @author transientlabs.xyz
interface ICreatorLookup {
    /// @notice Function to lookup the creator address for a given token
    /// @dev Should return the null address if the creator can't be determined
    function getCreator(address nftAddress, uint256 tokenId) external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IRoyaltyEngineV1.sol
/// @notice Minimal interface for the Manifold Royalty Registry's royalty engine
/// @dev Subset of https://github.com/manifoldxyz/royalty-registry-solidity/blob/main/contracts/IRoyaltyEngineV1.sol
/// @author manifold.xyz
interface IRoyaltyEngineV1 {
    /// @notice Get the royalty for a given token and value, caching the royalty spec for the token address
    /// @param tokenAddress The address of the token
    /// @param tokenId The id of the token
    /// @param value The value to get the royalty of
    /// @return recipients The royalty recipients
    /// @return amounts The amount each recipient should receive
    function getRoyalty(address tokenAddress, uint256 tokenId, uint256 value)
        external
        returns (address payable[] memory recipients, uint256[] memory amounts);

    /// @notice View only version of `getRoyalty`
    /// @param tokenAddress The address of the token
    /// @param tokenId The id of the token
    /// @param value The value to get the royalty of
    /// @return recipients The royalty recipients
    /// @return amounts The amount each recipient should receive
    function getRoyaltyView(address tokenAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory recipients, uint256[] memory amounts);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRoyaltyEngine {

    function getRoyalty(address nft, uint256 tokenId, uint256 value) external returns (address[] memory recipients, uint256[] memory amounts);

}
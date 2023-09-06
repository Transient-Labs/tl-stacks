// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DropType} from "./CommonUtils.sol";

/// @dev stacks drop struct
/// @param initialSupply The initial supply of the drop
/// @param supply The current supply left in the drop
/// @param allowance The allowance to mint per wallet during public mint
/// @param currencyAddress The currency address
/// @param payoutReceiver The address that receives the payout of the mint
/// @param startTime The time at which the drop opens
/// @param presaleDuration The duration for the presale phase of the drop
/// @param presaleCost The cost for each token in the presale phase
/// @param presaleMerkleRoot The merkle root for the presale phase of the drop
/// @param publicDuration The duration of the public sale phase
/// @param publicCost The cost of each token during the public sale phase
struct Drop {
    DropType dropType;
    address payoutReceiver;
    uint256 initialSupply;
    uint256 supply;
    uint256 allowance;
    address currencyAddress;
    uint256 startTime;
    uint256 presaleDuration;
    uint256 presaleCost;
    bytes32 presaleMerkleRoot;
    uint256 publicDuration;
    uint256 publicCost;
    int256 decayRate;
}

interface ITLStacks1155Events {
    event WethUpdated(address indexed prevWeth, address indexed newWeth);
    event ProtocolFeeUpdated(address indexed newProtocolFeeReceiver, uint256 indexed newProtocolFee);

    event DropConfigured(address indexed nftAddress, uint256 indexed tokenId, Drop drop);
    event DropUpdated(address indexed nftAddress, uint256 indexed tokenId, Drop drop);
    event DropClosed(address indexed nftAddress, uint256 indexed tokenId);

    event Purchase(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address nftReceiver,
        address currencyAddress,
        uint256 amount,
        uint256 price,
        int256 decayRate,
        bool isPresale
    );
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DropType} from "./CommonUtils.sol";

/// @dev stacks drop struct
/// @param initialSupply The initial supply of the drop
/// @param supply The current supply left in the drop
/// @param allowance The number of tokens each wallet can mint during the public phase. This is separate from
///        presale mints, which are capped per wallet by the presale merkle leaf.
/// @param currencyAddress The currency address
/// @param payoutReceiver The address that receives the payout of the mint
/// @param startTime The time at which the drop opens
/// @param presaleDuration The duration for the presale phase of the drop
/// @param presaleCost The cost for each token in the presale phase
/// @param presaleMerkleRoot The merkle root for the presale phase of the drop
/// @param publicDuration The duration of the public sale phase
/// @param publicCost The cost of each token during the public sale phase
/// @param baseUri The base uri for the folder to use for mint (NO TRAILING SLASH "/"). Token uris are built as
///        `baseUri + "/" + counter`. For an unnumbered edition, set this to the uri of a single metadata json
///        followed by a "#" (e.g. `ar://<id>#`). The counter then lands in the uri fragment, which isn't sent when
///        the uri is fetched, so every token resolves to the same metadata. This allows open ended supply, such as
///        velocity drops, without needing a pre-generated metadata file per token.
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
    string baseUri;
}

interface ITLStacks721Events {
    event ProtocolFeeUpdated(
        address indexed newProtocolFeeReceiver,
        uint256 newProtocolFee,
        uint256 newEthSellerFeeBps,
        uint256 newErc20SellerFeeBps
    );
    event SellerFeeWaived(address indexed nftAddress, uint256 indexed round);
    event ProtocolFeeSplitsUpdated(uint256 indexed freeMintFeeSplit, uint256 indexed referralFeeSplit);
    event DropConfigured(address indexed nftAddress, Drop drop);
    event DropUpdated(address indexed nftAddress, Drop drop);
    event DropClosed(address indexed nftAddress);
    event Purchase(
        address indexed nftAddress,
        address nftReceiver,
        address currencyAddress,
        uint256 amount,
        uint256 price,
        int256 decayRate,
        bool isPresale
    );
}

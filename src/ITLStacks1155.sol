// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITLStacks1155Events} from "tl-stacks/utils/ITLStacks1155Events.sol";

struct Drop {
    uint256 supply;
    int256 decayRate;
    uint256 allowance;
    address payoutReceiver;
    uint256 startTime;
    uint256 presaleDuration;
    address currencyAddr;
    uint256 presaleCost;
    bytes32 presaleMerkleRoot;
    uint256 publicDuration;
    uint256 publicCost;
}

interface ITLStacks1155 is ITLStacks1155Events {

    enum DropPhase {
        NOT_CONFIGURED,
        BEFORE_SALE,
        PRESALE,
        PUBLIC_SALE,
        ENDED
    }

    enum DropParam {
        MERKLE_ROOT,
        ALLOWANCE,
        COST,
        CURRENCY_ADDRESS,
        DURATION,
        PAYOUT_ADDRESS
    }

    function setPaused(bool paused) external;

    function configureDrop(
        address _nftAddr,
        uint256 _tokenId,
        uint256 _supply,
        int256 _decayRate,
        uint256 _allowance,
        address _payoutReceiver,
        uint256 _startTime,
        uint256 _presaleDuration,
        address _currencyAddr,
        uint256 _presaleCost,
        bytes32 _presaleMerkleRoot,
        uint256 _publicDuration,
        uint256 _publicCost
    ) external;

    function closeDrop(address _nftAddr, uint256 _tokenId) external;

    function updateDropParam(
        address _nftAddr,
        uint256 _tokenId,
        DropPhase _phase,
        DropParam _param,
        bytes32 _paramValue
    ) external;

    function mint(
        address _nftAddr,
        uint256 _tokenId,
        uint256 _numMint,
        address _receiver,
        bytes32[] calldata _proof,
        uint256 _allowlistAllocation
    ) external payable;

    function getDrop(address _nftAddr, uint256 _tokenId)
        external
        view
        returns (Drop memory);

    function getNumMinted(
        address _nftAddr,
        uint256 _tokenId,
        address _user
    ) external view returns (uint256);

    function getDropPhase(address _nftAddr, uint256 _tokenId)
        external
        view
        returns (DropPhase);

    function isPaused() external view returns (bool);
}

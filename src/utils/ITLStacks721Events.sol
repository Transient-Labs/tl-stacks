// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

interface ITLStacks721Events {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event DropConfigured(
        address indexed configurer,
        address indexed nftContract,
        uint256 tokenId
    );

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nftContract,
        uint256 amount,
        uint256 price,
        bool isPresale
    );

    event DropClosed(
        address indexed closer,
        address indexed nftContract
    );

    event DropUpdated(uint256 dropPhase, uint256 dropParam, bytes32 value);

    event Paused(bool newStatus);
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITLStacks1155Events {
    event DropConfigured(
        address indexed configurer,
        address indexed nftContract,
        uint256 tokenId
    );

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        bool isPresale
    );

    event DropClosed(
        address indexed closer,
        address indexed nftContract,
        uint256 tokenId
    );

    event DropUpdated(uint256 dropPhase, uint256 dropParam, bytes32 value);

    event Paused(bool newStatus);
}

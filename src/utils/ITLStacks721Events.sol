// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITLStacks721Events {
    event DropConfigured(
        address indexed configurer,
        address indexed nftContract,
        address currencyAddr
    );

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nftContract,
        address currencyAddr,
        uint256 amount,
        uint256 price,
        bool isPresale
    );

    event DropClosed(
        address indexed closer,
        address indexed nftContract
    );

    event DropUpdated(address nftContract, uint256 dropPhase, uint256 dropParam, bytes32 value);

    event Paused(bool newStatus);
}

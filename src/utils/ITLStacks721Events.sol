// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ITLStacks721Events {
    event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

    event Paused(address indexed sender, bool indexed status);

    event DropConfigured(address indexed configurer, address indexed nft_addr, uint256 indexed block_number);

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nft_addr,
        address currency_addr,
        uint256 amount,
        uint256 price,
        bool is_presale
    );

    event DropClosed(address indexed closer, address indexed nft_addr);

    event DropUpdated(
        address indexed updater, address indexed nft_addr, uint256 dropPhase, uint256 dropParam, bytes32 value
    );
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

interface IEditionMinting1155Events {
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
}

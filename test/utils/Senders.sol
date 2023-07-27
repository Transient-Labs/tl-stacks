// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITLBuyNow} from "tl-stacks/utils/ITLBuyNow.sol";

contract RevertingSenderBN {

    ITLBuyNow _bn;

    constructor(address bn) {
        _bn = ITLBuyNow(bn);
    }

    receive() external payable {
        revert("nah bro");
    }

    function buy(address nft, uint256 tokenId) external payable {
        bytes32[] memory proof = new bytes32[](0);
        _bn.buy{value: msg.value}(nft, tokenId, msg.sender, proof);
    }
}

contract ReenteringSenderBN {

    ITLBuyNow _bn;
    address _nft;
    uint256 _tokenId;

    constructor(address bn) {
        _bn = ITLBuyNow(bn);
    }

    receive() external payable {
        bytes32[] memory proof = new bytes32[](0);
        _bn.buy(_nft, _tokenId, address(this), proof);
    }

    function buy(address nft, uint256 tokenId) external payable {
        _nft = nft;
        _tokenId = tokenId;
        bytes32[] memory proof = new bytes32[](0);
        _bn.buy{value: msg.value}(nft, tokenId, msg.sender, proof);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TLAuctionHouse} from "src/TLAuctionHouse.sol";

contract Receiver {
    event EthReceived(uint256 indexed amount);

    receive() external payable {
        emit EthReceived(msg.value);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("hehe sucks to suck");
    }
}

contract RevertingBidder {
    address public ah;

    constructor(address ah_) {
        ah = ah_;
    }

    receive() external payable {
        revert("hehe sucks to suck");
    }

    function bid(address nftAddress, uint256 tokenId, uint256 bid_) external payable {
        TLAuctionHouse(ah).bid{value: msg.value}(
            nftAddress, tokenId, address(0), bid_, TLAuctionHouse(ah).getListing(nftAddress, tokenId).id
        );
    }

    function claimFunds(address currencyAddress, address to) external {
        TLAuctionHouse(ah).claimFunds(currencyAddress, to);
    }
}

contract GriefingBidder {
    address public ah;

    event Grief();

    constructor(address ah_) {
        ah = ah_;
    }

    receive() external payable {
        for (uint256 i = 0; i < type(uint256).max; i++) {
            emit Grief();
        }
    }

    function bid(address nftAddress, uint256 tokenId, uint256 bid_) external payable {
        TLAuctionHouse(ah).bid{value: msg.value}(
            nftAddress, tokenId, address(0), bid_, TLAuctionHouse(ah).getListing(nftAddress, tokenId).id
        );
    }

    function claimFunds(address currencyAddress, address to) external {
        TLAuctionHouse(ah).claimFunds(currencyAddress, to);
    }
}

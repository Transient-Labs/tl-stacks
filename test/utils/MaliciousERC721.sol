// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC721} from "@openzeppelin-contracts-5.0.2/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin-contracts-5.0.2/access/Ownable.sol";

contract MaliciousERC721 is ERC721, Ownable {
    constructor() ERC721("Malicous", "MAL") Ownable(msg.sender) {}

    function mint(address to) external onlyOwner {
        _mint(to, 1);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        // do nothing
    }
}

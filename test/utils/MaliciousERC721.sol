// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC721} from "openzeppelin/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract MaliciousERC721 is ERC721, Ownable {
    bool public beMalicious;
    uint256 private _counter;

    constructor() ERC721("Malicous", "MAL") Ownable(msg.sender) {}

    function setBeMalicious(bool tf) external onlyOwner {
        beMalicious = tf;
    }

    function mint(address to) external onlyOwner {
        _counter += 1;
        _mint(to, _counter);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        address tokenOwner = _ownerOf(tokenId);
        require(_isAuthorized(tokenOwner, _msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        if (beMalicious) {
            _transfer(from, owner(), tokenId);
        } else {
            _transfer(from, to, tokenId);
        }
    }
}

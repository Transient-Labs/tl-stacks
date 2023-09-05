// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BlockList} from "../../src/BlockList.sol";
import {ERC721} from "openzeppelin/token/ERC721/ERC721.sol";
import {OwnableAccessControl} from "tl-sol-tools/access/OwnableAccessControl.sol";

contract BlockListMock is ERC721, OwnableAccessControl, BlockList {
    uint256 private _counter;

    constructor(address newBlockListRegistry)
        ERC721("Mock", "MOCK")
        OwnableAccessControl()
        BlockList(newBlockListRegistry)
    {}

    /// @inheritdoc BlockList
    function isBlockListAdmin(address potentialAdmin) public view override returns (bool) {
        return potentialAdmin == owner();
    }

    /// @dev mint function
    function mint() external onlyOwner {
        _counter++;
        _mint(msg.sender, _counter);
    }

    /// @dev blocked approvals
    function approve(address to, uint256 tokenId) public override notBlocked(to) {
        super.approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override notBlocked(operator) {
        super.setApprovalForAll(operator, approved);
    }
}

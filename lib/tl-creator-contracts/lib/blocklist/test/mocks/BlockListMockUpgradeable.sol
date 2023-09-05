// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BlockListUpgradeable} from "../../src/BlockListUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "openzeppelin-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableAccessControlUpgradeable} from "tl-sol-tools/upgradeable/access/OwnableAccessControlUpgradeable.sol";

contract BlockListMockUpgradeable is
    Initializable,
    ERC721Upgradeable,
    OwnableAccessControlUpgradeable,
    BlockListUpgradeable
{
    uint256 private _counter;

    function initialize(address newBlockListRegistry) external initializer {
        __ERC721_init("Mock", "MOCK");
        __OwnableAccessControl_init(msg.sender);
        __BlockList_init(newBlockListRegistry);
    }

    /// @inheritdoc BlockListUpgradeable
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

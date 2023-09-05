// SPDX-License-Identifier: MIT

/// @dev this contract does not have proper access control but is only for testing

pragma solidity 0.8.19;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {EIP2981TLUpgradeable} from "../../../src/upgradeable/royalties/EIP2981TLUpgradeable.sol";

contract MockEIP2981TLUpgradeable is Initializable, EIP2981TLUpgradeable {
    function initialize(address recipient, uint256 percentage) external initializer {
        __EIP2981TL_init(recipient, percentage);
    }

    /// @dev function to set new default royalties
    function setDefaultRoyalty(address recipient, uint256 percentage) external {
        _setDefaultRoyaltyInfo(recipient, percentage);
    }

    /// @dev function to set token specific royalties
    function setTokenRoyalty(uint256 tokenId, address recipient, uint256 percentage) external {
        _overrideTokenRoyaltyInfo(tokenId, recipient, percentage);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ICreatorLookup} from "./ICreatorLookup.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/// @title CreatorLookup.sol
/// @notice Contract to enable TLAuctionHouse to determine who the creator of the token is
/// @author transientlabs.xyz
/// @custom:version 2.6.0
contract CreatorLookup is ICreatorLookup {
    ///////////////////////////////////////////////////////////////////////////
    /// CONSTANTS
    ///////////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.6.0";

    ///////////////////////////////////////////////////////////////////////////
    /// LOOKUP FUNCTION
    ///////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICreatorLookup
    function getCreator(address nftAddress, uint256 /* tokenId */ ) external view returns (address) {
        // first make sure nftAddress is a contract
        if (nftAddress.code.length == 0) return address(0);

        // passthrough for Ownable `owner` function, with more functionality planned in the future
        try Ownable(nftAddress).owner() returns (address owner) {
            return owner;
        } catch {
            return address(0);
        }
    }
}

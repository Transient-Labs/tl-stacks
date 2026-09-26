// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ICreatorLookup} from "./ICreatorLookup.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

/// @title CreatorLookup.sol
/// @notice Contract to enable TLAuctionHouse to determine who the creator of the token is
/// @dev The creator is the collection's current `owner`, which fits single-creator collections such as
///      Transient Labs creator contracts. It has no token-level provenance, so for multi-creator collections, or
///      collections whose ownership has changed hands, the collection owner is treated as the creator of every
///      token and sales by the collection owner are treated as primary sales (no royalties).
/// @author Transient Labs, Inc.
/// @custom:version 2.6.0
contract CreatorLookup is ICreatorLookup {
    /////////////////////////////////////////////////////////////////////
    // CONSTANTS
    /////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.6.0";

    /////////////////////////////////////////////////////////////////////
    // LOOKUP FUNCTION
    /////////////////////////////////////////////////////////////////////

    /// @inheritdoc ICreatorLookup
    function getCreator(
        address nftAddress,
        uint256 /* tokenId */
    )
        external
        view
        returns (address)
    {
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

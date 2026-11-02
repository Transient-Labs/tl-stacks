// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IRoyaltyLookup} from "./IRoyaltyLookup.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IRoyaltyEngineV1} from "./IRoyaltyEngineV1.sol";
import {IERC2981} from "@openzeppelin-contracts-5.6.1/interfaces/IERC2981.sol";

/// @title RoyaltyLookup.sol
/// @notice Contract to enable TLAuctionHouse to determine royalties to payout on secondary sales
/// @author Transient Labs, Inc.
/// @custom:version 2.8.0
contract RoyaltyLookup is Ownable, IRoyaltyLookup {
    /////////////////////////////////////////////////////////////////////
    // CONSTANTS
    /////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.8.0";

    /////////////////////////////////////////////////////////////////////
    // STORAGE
    /////////////////////////////////////////////////////////////////////

    IRoyaltyEngineV1 public royaltyEngine;

    /////////////////////////////////////////////////////////////////////
    // CONSTRUCTOR
    /////////////////////////////////////////////////////////////////////

    constructor(address initOwner) Ownable(initOwner) {}

    /////////////////////////////////////////////////////////////////////
    // LOOKUP FUNCTION
    /////////////////////////////////////////////////////////////////////

    /// @inheritdoc IRoyaltyLookup
    function getRoyalty(address nftAddress, uint256 tokenId, uint256 value)
        external
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        if (address(royaltyEngine).code.length != 0) {
            try royaltyEngine.getRoyalty(nftAddress, tokenId, value) returns (
                address payable[] memory r, uint256[] memory a
            ) {
                if (_hasPayableRoyalty(r, a)) return (r, a);
            } catch {}
        }
        return _getERC2981RoyaltyInfo(nftAddress, tokenId, value);
    }

    /// @inheritdoc IRoyaltyLookup
    function getRoyaltyView(address nftAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        if (address(royaltyEngine).code.length != 0) {
            try royaltyEngine.getRoyaltyView(nftAddress, tokenId, value) returns (
                address payable[] memory r, uint256[] memory a
            ) {
                if (_hasPayableRoyalty(r, a)) return (r, a);
            } catch {}
        }
        return _getERC2981RoyaltyInfo(nftAddress, tokenId, value);
    }

    /////////////////////////////////////////////////////////////////////
    // ADMIN FUNCTION
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to set the royalty engine
    function setRoyaltyEngine(address royaltyEngine_) external onlyOwner {
        royaltyEngine = IRoyaltyEngineV1(royaltyEngine_);
    }

    /////////////////////////////////////////////////////////////////////
    // INTERNAL HELPERS
    /////////////////////////////////////////////////////////////////////

    /// @notice Internal function to check if an engine schedule is usable
    /// @dev True when the arrays match and at least one nonzero amount goes to a nonzero recipient
    function _hasPayableRoyalty(address payable[] memory recipients, uint256[] memory amounts)
        internal
        pure
        returns (bool)
    {
        if (recipients.length != amounts.length) return false;
        for (uint256 i = 0; i < amounts.length; ++i) {
            if (amounts[i] != 0 && recipients[i] != address(0)) return true;
        }
        return false;
    }

    /// @notice Internal function to get royalty info based on ERC-2981 specification
    /// @dev A reverting NFT yields empty arrays. A successful call with malformed return data reverts this lookup
    ///      while decoding; `TLAuctionHouse` calls this contract inside `try/catch`, so that sale pays no royalty.
    function _getERC2981RoyaltyInfo(address nftAddress, uint256 tokenId, uint256 value)
        internal
        view
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        // make sure nft address is not an EOA
        if (nftAddress.code.length == 0) return (recipients, amounts);

        try IERC2981(nftAddress).royaltyInfo(tokenId, value) returns (address r, uint256 a) {
            recipients = new address payable[](1);
            amounts = new uint256[](1);
            recipients[0] = payable(r);
            amounts[0] = a;
        } catch {}
    }
}

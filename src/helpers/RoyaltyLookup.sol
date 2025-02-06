// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IRoyaltyLookup} from "./IRoyaltyLookup.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IRoyaltyEngineV1} from "royalty-registry-solidity/IRoyaltyEngineV1.sol";
import {IEIP2981} from "tl-sol-tools/royalties/IEIP2981.sol";

/// @title RoyaltyLookup.sol
/// @notice Contract to enable TLAuctionHouse to determine royalties to payout on secondary sales
/// @author transientlabs.xyz
/// @custom:version 2.6.0
contract RoyaltyLookup is Ownable, IRoyaltyLookup {
    ///////////////////////////////////////////////////////////////////////////
    /// CONSTANTS
    ///////////////////////////////////////////////////////////////////////////

    string public constant VERSION = "2.6.0";

    ///////////////////////////////////////////////////////////////////////////
    /// STATE VARIABLES
    ///////////////////////////////////////////////////////////////////////////

    IRoyaltyEngineV1 public royaltyEngine;

    ///////////////////////////////////////////////////////////////////////////
    /// CONSTRUCTOR
    ///////////////////////////////////////////////////////////////////////////

    constructor(address initOwner) Ownable(initOwner) {}

    ///////////////////////////////////////////////////////////////////////////
    /// LOOKUP FUNCTION
    ///////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IRoyaltyLookup
    function getRoyalty(address nftAddress, uint256 tokenId, uint256 value)
        external
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        // if royalty registry is enabled, use that, otherwise fallback to ERC-2981
        if (address(royaltyEngine) != address(0)) {
            // make sure royalty engine is not an EOA
            if (address(royaltyEngine).code.length == 0) return (recipients, amounts);

            // try looking up royalty
            try royaltyEngine.getRoyalty(nftAddress, tokenId, value) returns (
                address payable[] memory r, uint256[] memory a
            ) {
                // if array lengths don't match, return empty
                if (r.length != a.length) return (recipients, amounts);

                // return values from the royalty registry otherwise
                return (r, a);
            } catch {
                // if error, return empty
                return (recipients, amounts);
            }
        } else {
            return _getERC2981RoyaltyInfo(nftAddress, tokenId, value);
        }
    }

    /// @inheritdoc IRoyaltyLookup
    function getRoyaltyView(address nftAddress, uint256 tokenId, uint256 value)
        external
        view
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        // if royalty registry is enabled, use that, otherwise fallback to ERC-2981
        if (address(royaltyEngine) != address(0)) {
            // make sure royalty engine is not an EOA
            if (address(royaltyEngine).code.length == 0) return (recipients, amounts);

            // try looking up royalty
            try royaltyEngine.getRoyaltyView(nftAddress, tokenId, value) returns (
                address payable[] memory r, uint256[] memory a
            ) {
                // if array lengths don't match, return empty
                if (r.length != a.length) return (recipients, amounts);

                // return values from the royalty registry otherwise
                return (r, a);
            } catch {
                // if error, return empty
                return (recipients, amounts);
            }
        } else {
            return _getERC2981RoyaltyInfo(nftAddress, tokenId, value);
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// ADMIN FUNCTION
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Function to set the royalty engine
    function setRoyaltyEngine(address royaltyEngine_) external onlyOwner {
        royaltyEngine = IRoyaltyEngineV1(royaltyEngine_);
    }

    ///////////////////////////////////////////////////////////////////////////
    /// INTERNAL HELPERS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Internal function to get royalty info based on ERC-2981 specification
    function _getERC2981RoyaltyInfo(address nftAddress, uint256 tokenId, uint256 value)
        internal
        view
        returns (address payable[] memory recipients, uint256[] memory amounts)
    {
        // make sure nft address is not an EOA
        if (nftAddress.code.length == 0) return (recipients, amounts);

        // try looking up royalty
        try IEIP2981(nftAddress).royaltyInfo(tokenId, value) returns (address r_, uint256 a_) {
            // convert return value to arrays
            address payable[] memory r = new address payable[](1);
            r[0] = payable(r_);
            uint256[] memory a = new uint256[](1);
            a[0] = a_;

            // return arrays
            return (r, a);
        } catch {
            // if error, return empty
            return (recipients, amounts);
        }
    }
}

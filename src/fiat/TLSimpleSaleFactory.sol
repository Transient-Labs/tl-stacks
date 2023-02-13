// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {OwnableAccessControl} from "tl-sol-tools/access/OwnableAccessControl.sol";
import {TLSimpleSale} from "tl-stacks/fiat/TLSimpleSale.sol";
import {ClonesUpgradeable} from "openzeppelin-upgradeable/proxy/ClonesUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

/*
    ____        _ __    __   ____  _ ________                     __ 
   / __ )__  __(_) /___/ /  / __ \(_) __/ __/__  ________  ____  / /_
  / __  / / / / / / __  /  / / / / / /_/ /_/ _ \/ ___/ _ \/ __ \/ __/
 / /_/ / /_/ / / / /_/ /  / /_/ / / __/ __/  __/ /  /  __/ / / / /__ 
/_____/\__,_/_/_/\__,_/  /_____/_/_/ /_/  \___/_/   \___/_/ /_/\__(_)*/

/// @title TLSimpleSale.sol
/// @notice Transient Labs Contract for a Simple Sale Factory
/// @author transientlabs.xyz
contract TLSimpleSaleFactory is OwnableAccessControl, Initializable {
    /*//////////////////////////////////////////////////////////////////////////
                                    Errors
    //////////////////////////////////////////////////////////////////////////*/
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////////////////
                                State Variables
    //////////////////////////////////////////////////////////////////////////*/
    address public simpleSaleTemplate;

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _disable: boolean to disable initialization for the implementation contract
    constructor(bool _disable) {
        if (_disable) _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Admin Function
    //////////////////////////////////////////////////////////////////////////*/

    function updateSaleTemplate(address _newTemplate) external onlyOwner {
        simpleSaleTemplate = _newTemplate;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Create Function
    //////////////////////////////////////////////////////////////////////////*/

    function createSale(
        address _nftContract,
        uint256 _tokenId,
        address _currencyAddress,
        uint256 _cost,
        address _payoutReceiver
    ) external {
        address sale = ClonesUpgradeable.clone(simpleSaleTemplate);

        if (
            msg.sender != OwnableAccessControl(_nftContract).owner() &&
            !OwnableAccessControl(_nftContract).hasRole(
                keccak256("ADMIN_ROLE"),
                msg.sender
            )
        ) {
            revert Unauthorized();
        }

        TLSimpleSale(sale).initialize(
            _nftContract,
            _tokenId,
            _currencyAddress,
            _cost,
            _payoutReceiver
        );
    }
}

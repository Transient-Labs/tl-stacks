// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {SafeERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {ERC1155TL} from "tl-core/ERC1155TL.sol";

/*
    ____        _ __    __   ____  _ ________                     __ 
   / __ )__  __(_) /___/ /  / __ \(_) __/ __/__  ________  ____  / /_
  / __  / / / / / / __  /  / / / / / /_/ /_/ _ \/ ___/ _ \/ __ \/ __/
 / /_/ / /_/ / / / /_/ /  / /_/ / / __/ __/  __/ /  /  __/ / / / /__ 
/_____/\__,_/_/_/\__,_/  /_____/_/_/ /_/  \___/_/   \___/_/ /_/\__(_)*/

/// @title TLSimpleSale.sol
/// @notice Transient Labs Contract for a Simple Sale
/// @author transientlabs.xyz
contract TLSimpleSale is ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                    Errors
    //////////////////////////////////////////////////////////////////////////*/
    error InsufficientAmount(
        address _currencyAddress,
        uint256 _requireAmt,
        uint256 _providedAmt
    );

    error WrongCurrency();

    /*//////////////////////////////////////////////////////////////////////////
                                State Variables
    //////////////////////////////////////////////////////////////////////////*/
    ERC1155TL public nftContract;
    uint256 public tokenId;
    address public currencyAddress;
    uint256 public cost;
    address public payoutReceiver;

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _disable: boolean to disable initialization for the implementation contract
    constructor(bool _disable) {
        if (_disable) _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Initializer
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _nftContract: Adddress of the nft contract to use
    /// @param _tokenId: Token Id of nft being configured for sale
    /// @param _currencyAddress: Address of currency for sale
    /// @param _cost: Cost of sale
    function initialize(
        address _nftContract,
        uint256 _tokenId,
        address _currencyAddress,
        uint256 _cost,
        address _payoutReceiver
    ) external initializer {
        nftContract = ERC1155TL(_nftContract);
        tokenId = _tokenId;
        currencyAddress = _currencyAddress;
        cost = _cost;
        payoutReceiver = _payoutReceiver;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Purchase Function
    //////////////////////////////////////////////////////////////////////////*/

    function mint(address _to) public payable {
        mint(_to, 1);
    }

    function mint(address _to, uint256 _qty) public payable nonReentrant {
        if (currencyAddress == address(0)) {
            if (msg.value < _qty * cost) {
                revert InsufficientAmount(
                    currencyAddress,
                    _qty * cost,
                    msg.value
                );
            }
        } else {
            if (msg.value != 0) revert WrongCurrency();

            IERC20Upgradeable erc20 = IERC20Upgradeable(currencyAddress);
            if (
                erc20.allowance(msg.sender, address(this)) < _qty * cost ||
                erc20.balanceOf(msg.sender) < _qty * cost
            ) {
                revert InsufficientAmount(
                    currencyAddress,
                    _qty * cost,
                    msg.value
                );
            }
        }

        address[] memory addrs = new address[](1);
        addrs[0] = _to;

        uint256[] memory amts = new uint256[](1);
        amts[0] = _qty;

        ERC1155TL(nftContract).externalMint(tokenId, addrs, amts);

        if (currencyAddress == address(0)) {
            (bool success,) = payoutReceiver.call{value: msg.value}("");
            require(success);
        } else {
            IERC20Upgradeable erc20 = IERC20Upgradeable(currencyAddress);
            erc20.safeTransferFrom(msg.sender, payoutReceiver, _qty * cost);
        }
    }
}

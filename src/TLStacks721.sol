// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Pausable} from "openzeppelin/utils/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/utils/ReentrancyGuard.sol";
import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {IERC721TL} from "tl-creator-contracts/erc-721/IERC721TL.sol";
import {TransferHelper} from "tl-sol-tools/payments/TransferHelper.sol";
import {SanctionsCompliance} from "tl-sol-tools/payments/SanctionsCompliance.sol";
import {OwnableAccessControl} from "tl-sol-tools/access/OwnableAccessControl.sol";
import {DropPhase, DropType, DropErrors} from "./utils/CommonUtils.sol";
import {Drop, ITLStacks721Events} from "./utils/TLStacks721Utils.sol";

/*//////////////////////////////////////////////////////////////////////////
                            TL Stacks 1155
//////////////////////////////////////////////////////////////////////////*/

/// @title TLStacks721
/// @notice Transient Labs Stacks mint contract for ERC721TL-based contracts
/// @author transientlabs.xyz
/// @custom:version-last-updated 2.3.0
contract TLStacks721 is
    Ownable,
    Pausable,
    ReentrancyGuard,
    TransferHelper,
    SanctionsCompliance,
    ITLStacks721Events,
    DropErrors
{
    /*//////////////////////////////////////////////////////////////////////////
                                  Constants
    //////////////////////////////////////////////////////////////////////////*/

    using Strings for uint256;

    string public constant VERSION = "2.3.0";
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant APPROVED_MINT_CONTRACT = keccak256("APPROVED_MINT_CONTRACT");

    /*//////////////////////////////////////////////////////////////////////////
                                State Variables
    //////////////////////////////////////////////////////////////////////////*/

    address public protocolFeeReceiver; // the payout receiver for the protocol fee
    uint256 public protocolFee; // the protocol fee, in eth, to charge the buyer
    address public weth; // weth address
    mapping(address => Drop) internal _drops; // nft address -> Drop
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal _numberMinted; // nft address -> round -> user -> number minted
    mapping(address => uint256) internal _rounds; // nft address -> round

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    constructor(
        address initOwner,
        address initSanctionsOracle,
        address initWethAddress,
        address initProtocolFeeReceiver,
        uint256 initProtocolFee
    ) Ownable(initOwner) Pausable() ReentrancyGuard() SanctionsCompliance(initSanctionsOracle) {
        _setWethAddress(initWethAddress);
        _setProtocolFeeSettings(initProtocolFeeReceiver, initProtocolFee);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Owner Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to set a new weth address
    /// @dev Requires owner
    /// @param newWethAddress The new weth address
    function setWethAddress(address newWethAddress) external onlyOwner {
        _setWethAddress(newWethAddress);
    }

    /// @notice Function to set the protocol fee settings
    /// @dev Requires owner
    /// @param newProtocolFeeReceiver The new protocol fee receiver
    /// @param newProtocolFee The new protocol fee in ETH
    function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFee) external onlyOwner {
        _setProtocolFeeSettings(newProtocolFeeReceiver, newProtocolFee);
    }

    /// @notice Function to pause the contract
    /// @dev Requires owner
    /// @param status The boolean to set the internal pause variable
    function pause(bool status) external onlyOwner {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Function to set the sanctions oracle
    /// @dev Requires owner
    /// @param newOracle The new oracle address
    function setSanctionsOracle(address newOracle) external onlyOwner {
        _updateSanctionsOracle(newOracle);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            Drop Configuration Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to configure a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @dev Reverts if
    ///     - the payout receiver is the zero address
    ///     - a drop is already configured and live
    ///     - the `intialSupply` does not equal the `supply`
    ///     - the `decayRate` is non-zero and there is a presale configured
    /// @param nftAddress The nft contract address
    /// @param drop The drop to configure
    function configureDrop(address nftAddress, Drop calldata drop) external whenNotPaused nonReentrant {
        // sanctions
        _isSanctioned(msg.sender, true);
        _isSanctioned(drop.payoutReceiver, true);

        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        if (!_isApprovedMintContract(nftAddress)) revert NotApprovedMintContract();
        if (!_checkPayoutReceiver(drop.payoutReceiver)) revert InvalidPayoutReceiver();
        if (drop.initialSupply != drop.supply) revert InvalidDropSupply();
        if (drop.decayRate != 0 && drop.dropType != DropType.VELOCITY) revert InvalidDropType();
        if (drop.dropType == DropType.VELOCITY && drop.presaleDuration != 0) revert NotAllowedForVelocityDrops();

        // check if drop is already configured and live
        Drop memory mDrop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(mDrop);
        if (mDrop.dropType != DropType.NOT_CONFIGURED && mPhase != DropPhase.ENDED) {
            revert DropAlreadyConfigured();
        }

        // store drop
        _drops[nftAddress] = drop;

        // increment drop round if drop was previously set
        if (mDrop.dropType != DropType.NOT_CONFIGURED) {
            _rounds[nftAddress] += 1;
        }

        emit DropConfigured(nftAddress, drop);
    }

    /// @notice Function to update the payout receiver of a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param payoutReceiver The recipient of the funds from the mint
    function updateDropPayoutReceiver(address nftAddress, address payoutReceiver) external whenNotPaused nonReentrant {
        // sanctions
        _isSanctioned(payoutReceiver, true);

        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (!_checkPayoutReceiver(payoutReceiver)) revert InvalidPayoutReceiver();

        // set new payout receiver
        drop.payoutReceiver = payoutReceiver;
        _drops[nftAddress].payoutReceiver = drop.payoutReceiver;

        emit DropUpdated(nftAddress, drop);
    }

    /// @notice Function to update the drop public allowance
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param allowance The number of tokens allowed to be minted per wallet during the public phase of the drop
    function updateDropAllowance(address nftAddress, uint256 allowance) external whenNotPaused nonReentrant {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();

        // set new allowance
        drop.allowance = allowance;
        _drops[nftAddress].allowance = drop.allowance;

        emit DropUpdated(nftAddress, drop);
    }

    /// @notice Function to update the drop prices and currency
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param currencyAddress The currency address (zero address represents ETH)
    /// @param presaleCost The cost of each token during the presale phase
    /// @param publicCost The cost of each token during the presale phase
    function updateDropPrices(address nftAddress, address currencyAddress, uint256 presaleCost, uint256 publicCost)
        external
        whenNotPaused
        nonReentrant
    {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();

        // set currency address and prices
        drop.currencyAddress = currencyAddress;
        drop.presaleCost = presaleCost;
        drop.publicCost = publicCost;
        _drops[nftAddress].currencyAddress = drop.currencyAddress;
        _drops[nftAddress].presaleCost = drop.presaleCost;
        _drops[nftAddress].publicCost = drop.publicCost;

        emit DropUpdated(nftAddress, drop);
    }

    /// @notice Function to adjust drop durations
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param startTime The timestamp at which the drop starts
    /// @param presaleDuration The duration of the presale phase of the drop, in seconds
    /// @param publicDuration The duration of the public phase
    function updateDropDuration(address nftAddress, uint256 startTime, uint256 presaleDuration, uint256 publicDuration)
        external
        whenNotPaused
        nonReentrant
    {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (drop.dropType == DropType.VELOCITY && presaleDuration != 0) revert NotAllowedForVelocityDrops();

        // update durations
        drop.startTime = startTime;
        drop.presaleDuration = presaleDuration;
        drop.publicDuration = publicDuration;
        _drops[nftAddress].startTime = drop.startTime;
        _drops[nftAddress].presaleDuration = drop.presaleDuration;
        _drops[nftAddress].publicDuration = drop.publicDuration;

        emit DropUpdated(nftAddress, drop);
    }

    /// @notice Function to alter a drop merkle root
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param presaleMerkleRoot The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropPresaleMerkleRoot(address nftAddress, bytes32 presaleMerkleRoot)
        external
        whenNotPaused
        nonReentrant
    {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (drop.dropType == DropType.VELOCITY) revert NotAllowedForVelocityDrops();

        // update merkle root
        drop.presaleMerkleRoot = presaleMerkleRoot;
        _drops[nftAddress].presaleMerkleRoot = drop.presaleMerkleRoot;

        emit DropUpdated(nftAddress, drop);
    }

    /// @notice Function to adjust the drop decay rate
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param decayRate The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropDecayRate(address nftAddress, int256 decayRate) external whenNotPaused nonReentrant {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (drop.dropType != DropType.VELOCITY) revert NotAllowedForVelocityDrops();

        // update decay rate
        drop.decayRate = decayRate;
        _drops[nftAddress].decayRate = drop.decayRate;

        emit DropUpdated(nftAddress, drop);
    }

    function closeDrop(address nftAddress) external nonReentrant {
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();

        // delete the drop
        delete _drops[nftAddress];

        // clear the number minted round
        _rounds[nftAddress]++;

        emit DropClosed(nftAddress);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Purchase Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to purchase tokens on a drop
    /// @dev Reverts on any of the following conditions
    ///     - Drop isn't active or configured
    ///     - numberToMint is 0
    ///     - Invalid merkle proof during the presale phase
    ///     - Insufficent protocol fee
    ///     - Insufficient funds
    ///     - Already minted the allowance for the recipient
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    /// @return refundAmount The amount of eth refunded to the caller
    function purchase(
        address nftAddress,
        address recipient,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] calldata proof
    ) external payable whenNotPaused nonReentrant returns (uint256 refundAmount) {
        _isSanctioned(msg.sender, true);
        _isSanctioned(recipient, true);

        // cache drop
        Drop memory drop = _drops[nftAddress];
        DropPhase dropPhase = _getDropPhase(drop);
        uint256 round = _rounds[nftAddress];
        uint256 numberMinted = _numberMinted[nftAddress][round][recipient];
        uint256 numberCanMint = numberToMint; // cache and then update depending on phase
        uint256 cost = drop.presaleCost;

        // pre-conditions - revert for safety and expected behavior from users - UX for batch purchases needs to be smart in order to avoid reverting conditions
        if (numberToMint == 0) revert MintZeroTokens();
        if (dropPhase == DropPhase.PRESALE) {
            bytes32 leaf = keccak256(abi.encode(keccak256(abi.encode(recipient)), presaleNumberCanMint));
            if (!MerkleProof.verify(proof, drop.presaleMerkleRoot, leaf)) revert NotOnAllowlist();
            numberCanMint = _getNumberCanMint(presaleNumberCanMint, numberMinted, drop.supply);
        } else if (dropPhase == DropPhase.PUBLIC_SALE) {
            numberCanMint = _getNumberCanMint(drop.allowance, numberMinted, drop.supply);
            cost = drop.publicCost;
        } else {
            revert YouShallNotMint();
        }
        if (numberCanMint == 0) revert AlreadyReachedMintAllowance();

        // limit numberToMint to numberCanMint
        if (numberToMint > numberCanMint) {
            numberToMint = numberCanMint;
        }

        // adjust drop state
        _updateDropState(nftAddress, round, recipient, numberToMint, drop);

        // settle funds
        refundAmount = _settleUp(numberToMint, cost, drop);

        // mint
        _mintToken(nftAddress, recipient, numberToMint, drop);

        emit Purchase(
            nftAddress,
            recipient,
            drop.currencyAddress,
            numberToMint,
            cost,
            drop.decayRate,
            dropPhase == DropPhase.PRESALE
        );

        return refundAmount;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            External View Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to get a drop
    /// @param nftAddress The nft contract address
    /// @return Drop The drop for the nft contract and token id
    function getDrop(address nftAddress) external view returns (Drop memory) {
        return _drops[nftAddress];
    }

    /// @notice Function to get number minted on a drop for an address
    /// @param nftAddress The nft contract address
    /// @param recipient The recipient of the nft
    /// @return uint256 The number of tokens minted
    function getNumberMinted(address nftAddress, address recipient) external view returns (uint256) {
        uint256 round = _rounds[nftAddress];
        return _numberMinted[nftAddress][round][recipient];
    }

    /// @notice Function to get the drop phase
    /// @param nftAddress The nft contract address
    /// @return DropPhase The drop phase
    function getDropPhase(address nftAddress) external view returns (DropPhase) {
        Drop memory drop = _drops[nftAddress];
        return _getDropPhase(drop);
    }

    /// @notice Function to get the drop round
    /// @param nftAddress The nft contract address
    /// @return uint256 The round for the drop based on the nft contract and token id
    function getDropRound(address nftAddress) external view returns (uint256) {
        return _rounds[nftAddress];
    }

    /*//////////////////////////////////////////////////////////////////////////
                            Internal Helper Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Internal function to set the weth address
    /// @param newWethAddress The new weth address
    function _setWethAddress(address newWethAddress) internal {
        address prevWethAddress = weth;
        weth = newWethAddress;

        emit WethUpdated(prevWethAddress, newWethAddress);
    }

    /// @notice Internal function to set the protocol fee settings
    /// @param newProtocolFeeReceiver The new protocol fee receiver
    /// @param newProtocolFee The new protocol fee in ETH
    function _setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFee) internal {
        protocolFeeReceiver = newProtocolFeeReceiver;
        protocolFee = newProtocolFee;

        emit ProtocolFeeUpdated(newProtocolFeeReceiver, newProtocolFee);
    }

    /// @notice Internal function to check if msg.sender is the owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @return bool Boolean indicating if msg.sender is the owner or an admin on the nft contract
    function _isDropAdmin(address nftAddress) internal view returns (bool) {
        return (
            msg.sender == OwnableAccessControl(nftAddress).owner()
                || OwnableAccessControl(nftAddress).hasRole(ADMIN_ROLE, msg.sender)
        );
    }

    /// @notice Intenral function to check if this contract is an approved mint contract
    /// @param nftAddress The nft contract address
    /// @return bool Boolean indicating if this contract is approved or not
    function _isApprovedMintContract(address nftAddress) internal view returns (bool) {
        return OwnableAccessControl(nftAddress).hasRole(APPROVED_MINT_CONTRACT, address(this));
    }

    /// @notice Internal function to check if a payout address is a valid address
    /// @param payoutReceiver The payout address to check
    /// @return bool Indication of if the payout address is not the zero address
    function _checkPayoutReceiver(address payoutReceiver) internal pure returns (bool) {
        return payoutReceiver != address(0);
    }

    /// @notice Internal function to get the drop phase
    /// @param drop The drop in question
    /// @return DropPhase The drop phase enum value
    function _getDropPhase(Drop memory drop) internal view returns (DropPhase) {
        if (drop.payoutReceiver == address(0)) return DropPhase.NOT_CONFIGURED;
        if (drop.supply == 0) return DropPhase.ENDED;
        if (block.timestamp < drop.startTime) return DropPhase.NOT_STARTED;
        if (block.timestamp >= drop.startTime && block.timestamp < drop.startTime + drop.presaleDuration) {
            return DropPhase.PRESALE;
        }
        if (
            block.timestamp >= drop.startTime + drop.presaleDuration
                && block.timestamp < drop.startTime + drop.presaleDuration + drop.publicDuration
        ) return DropPhase.PUBLIC_SALE;
        return DropPhase.ENDED;
    }

    /// @notice Internal function to determine how many tokens can be minted by an address
    /// @param allowance The amount allowed to mint
    /// @param numberMinted The amount already minted
    /// @param supply The drop supply
    /// @return numberCanMint The number of tokens allowed to mint
    function _getNumberCanMint(uint256 allowance, uint256 numberMinted, uint256 supply)
        internal
        pure
        returns (uint256 numberCanMint)
    {
        if (numberMinted < allowance) {
            numberCanMint = allowance - numberMinted;
            if (numberCanMint > supply) {
                numberCanMint = supply;
            }
        } else {
            numberCanMint = 0;
        }
    }

    /// @notice Function to update the state of the drop
    /// @param nftAddress The nft contract address
    /// @param round The drop round for number minted
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param drop The Drop cached in memory
    function _updateDropState(
        address nftAddress,
        uint256 round,
        address recipient,
        uint256 numberToMint,
        Drop memory drop
    ) internal {
        // velocity mint
        if (drop.dropType == DropType.VELOCITY) {
            uint256 durationAdjust = drop.decayRate < 0
                ? uint256(-1 * drop.decayRate) * numberToMint
                : uint256(drop.decayRate) * numberToMint;
            if (drop.decayRate < 0) {
                if (durationAdjust > drop.publicDuration) {
                    _drops[nftAddress].publicDuration = 0;
                } else {
                    _drops[nftAddress].publicDuration -= durationAdjust;
                }
            } else {
                _drops[nftAddress].publicDuration += durationAdjust;
            }
        }

        // regular state (applicable to all types of drops)
        _drops[nftAddress].supply -= numberToMint;
        _numberMinted[nftAddress][round][recipient] += numberToMint;
    }

    /// @notice Internal function to distribute funds for a _purchase
    /// @param numberToMint The number of tokens that can be minted
    /// @param cost The cost per token
    /// @param drop The drop
    /// @return refundAmount The amount of eth refunded to msg.sender
    function _settleUp(uint256 numberToMint, uint256 cost, Drop memory drop) internal returns (uint256 refundAmount) {
        uint256 totalProtocolFee = numberToMint * protocolFee;
        uint256 totalSale = numberToMint * cost;
        if (drop.currencyAddress == address(0)) {
            uint256 totalCost = totalSale + totalProtocolFee;
            if (msg.value < totalCost) revert InsufficientFunds();
            _safeTransferETH(drop.payoutReceiver, totalSale, weth);
            refundAmount = msg.value - totalCost;
        } else {
            if (msg.value < totalProtocolFee) revert InsufficientFunds();
            _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
            refundAmount = msg.value - totalProtocolFee;
        }
        _safeTransferETH(protocolFeeReceiver, totalProtocolFee, weth);
        if (refundAmount > 0) {
            _safeTransferETH(msg.sender, refundAmount, weth);
        }
        return refundAmount;
    }

    /// @notice Internal function to mint the token
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param drop The drop cached in memory (not read from storage again)
    function _mintToken(address nftAddress, address recipient, uint256 numberToMint, Drop memory drop) internal {
        uint256 uriCounter = drop.initialSupply - drop.supply;
        for (uint256 i = 0; i < numberToMint; i++) {
            IERC721TL(nftAddress).externalMint(
                recipient, string(abi.encodePacked(drop.baseUri, "/", (uriCounter + i).toString()))
            );
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {TransferHelper} from "tl-sol-tools/payments/TransferHelper.sol";
import {OwnableAccessControl} from "tl-sol-tools/access/OwnableAccessControl.sol";
import {ERC721TL} from "tl-creator-contracts/core/ERC721TL.sol";
import {DropPhase, DropType, DropErrors} from "tl-stacks/utils/CommonUtils.sol";
import {Drop, ITLStacks721Events} from "tl-stacks/utils/TLStacks721Utils.sol";

/*//////////////////////////////////////////////////////////////////////////
                            TL Stacks 1155
//////////////////////////////////////////////////////////////////////////*/

/// @title TLStacks721
/// @notice Transient Labs Stacks mint contract for ERC721TL-based contracts
/// @author transientlabs.xyz
/// @custom:version-last-updated 2.0.0
contract TLStacks721 is Ownable, Pausable, ReentrancyGuard, TransferHelper, ITLStacks721Events, DropErrors {
    /*//////////////////////////////////////////////////////////////////////////
                                  Constants
    //////////////////////////////////////////////////////////////////////////*/

    using Strings for uint256;

    string public constant VERSION = "2.0.0";
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant APPROVED_MINT_CONTRACT = keccak256("APPROVED_MINT_CONTRACT");

    /*//////////////////////////////////////////////////////////////////////////
                                State Variables
    //////////////////////////////////////////////////////////////////////////*/

    address public protocolFeeReceiver; // the payout receiver for the protocol fee
    uint256 public protocolFee; // the protocol fee, in eth, to charge the buyer
    address public wethAddress; // weth address
    mapping(address => Drop) internal _drops; // nft address -> Drop
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal _numberMinted; // nft address -> round -> user -> number minted
    mapping(address => uint256) internal _rounds; // nft address -> round

    /*//////////////////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address initWethAddress, address initProtocolFeeReceiver, uint256 initProtocolFee)
        Ownable()
        Pausable()
        ReentrancyGuard()
    {
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

    /*//////////////////////////////////////////////////////////////////////////
                            Drop Configuration Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to configure a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @dev Reverts if
    ///     - the payout receiver is the zero address
    ///     - a drop is already configured
    ///     - the `intiialSupply` does not equal the `supply`
    ///     - the `decayRate` is non-zero and there is a presale configured
    /// @param nftAddress The nft contract address
    /// @param drop The drop to configure
    function configureDrop(address nftAddress, Drop calldata drop) external whenNotPaused {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        if (!_checkPayoutReceiver(drop.payoutReceiver)) revert InvalidPayoutReceiver();
        if (drop.initialSupply != drop.supply) revert InvalidDropSupply();
        if (drop.decayRate != 0 && drop.dropType != DropType.VELOCITY) revert InvalidDropType();
        if (drop.dropType != DropType.VELOCITY && drop.presaleDuration != 0) revert NotAllowedForVelocityDrops();

        // check if drop is already configured
        Drop memory mDrop = _drops[nftAddress];
        if (mDrop.dropType != DropType.NOT_CONFIGURED) revert DropAlreadyConfigured();

        // store drop
        _drops[nftAddress] = drop;

        emit DropConfigured(msg.sender, nftAddress, drop);
    }

    /// @notice Function to update the payout receiver of a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param payoutReceiver The recipient of the funds from the mint
    function updateDropPayoutReceiver(address nftAddress, address payoutReceiver) external whenNotPaused {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();
        if (!_checkPayoutReceiver(payoutReceiver)) revert InvalidPayoutReceiver();

        // set new payout receiver
        drop.payoutReceiver = payoutReceiver;
        _drops[nftAddress].payoutReceiver = drop.payoutReceiver;

        emit DropUpdated(msg.sender, nftAddress, drop);
    }

    /// @notice Function to update the drop public allowance
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param allowance The number of tokens allowed to be minted per wallet during the public phase of the drop
    function updateDropAllowance(address nftAddress, uint256 allowance) external whenNotPaused {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();

        // set new allowance
        drop.allowance = allowance;
        _drops[nftAddress].allowance = drop.allowance;

        emit DropUpdated(msg.sender, nftAddress, drop);
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
    {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();

        // set currency address and prices
        drop.currencyAddress = currencyAddress;
        drop.presaleCost = presaleCost;
        drop.publicCost = publicCost;
        _drops[nftAddress].currencyAddress = drop.currencyAddress;
        _drops[nftAddress].presaleCost = drop.presaleCost;
        _drops[nftAddress].publicCost = drop.publicCost;

        emit DropUpdated(msg.sender, nftAddress, drop);
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
    {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();
        if (presaleDuration != 0 && drop.dropType == DropType.VELOCITY) revert NotAllowedForVelocityDrops();

        // update durations
        drop.startTime = startTime;
        drop.presaleDuration = presaleDuration;
        drop.publicDuration = publicDuration;
        _drops[nftAddress].startTime = drop.startTime;
        _drops[nftAddress].presaleDuration = drop.presaleDuration;
        _drops[nftAddress].publicDuration = drop.publicDuration;

        emit DropUpdated(msg.sender, nftAddress, drop);
    }

    /// @notice Function to alter a drop merkle root
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param presaleMerkleRoot The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropPresaleMerkleRoot(address nftAddress, bytes32 presaleMerkleRoot) external whenNotPaused {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();

        // update merkle root
        drop.presaleMerkleRoot = presaleMerkleRoot;
        _drops[nftAddress].presaleMerkleRoot = drop.presaleMerkleRoot;

        emit DropUpdated(msg.sender, nftAddress, drop);
    }

    /// @notice Function to adjust the drop decay rate
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @param decayRate The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropDecayRate(address nftAddress, int256 decayRate) external whenNotPaused {
        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        if (_getDropPhase(drop) == DropPhase.NOT_CONFIGURED) revert DropNotConfigured();
        if (drop.dropType != DropType.VELOCITY) revert NotAllowedForVelocityDrops();

        // update decay rate
        drop.decayRate = decayRate;
        _drops[nftAddress].decayRate = drop.decayRate;

        emit DropUpdated(msg.sender, nftAddress, drop);
    }

    function closeDrop(address nftAddress) external {
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();

        // delete the drop
        delete _drops[nftAddress];

        // clear the number minted round
        _rounds[nftAddress]++;

        emit DropClosed(msg.sender, nftAddress);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                Purchase Functions
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Function to purchase a single token via a drop
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    function purchaseSingle(
        address nftAddress,
        address recipient,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] calldata proof
    ) external payable whenNotPaused nonReentrant {
        uint256 msgValueUsed = _purchase(nftAddress, recipient, numberToMint, presaleNumberCanMint, proof, msg.value);
        // refund
        uint256 refund = msg.value - msgValueUsed;
        if (refund > 0) {
            _safeTransferETH(msg.sender, refund, wethAddress);
        }
    }

    /// @notice Function to purchase a batch of tokens on a single nft contract
    /// @dev This is useful for puchasing tokens for a batch of different recipients
    /// @param nftAddress The nft contract address
    /// @param recipients The receiver of the nft (msg.sender is the payer but this allows delegation) for each token
    /// @param numbersToMint The number of each token to mint
    /// @param presaleNumbersCanMint The number of each token the recipient can mint during presale
    /// @param proofs The merkle proof for the presale page per token
    function purchaseBatch(
        address nftAddress,
        address[] calldata recipients,
        uint256[] calldata numbersToMint,
        uint256[] calldata presaleNumbersCanMint,
        bytes32[][] calldata proofs
    ) external payable whenNotPaused nonReentrant {
        // check that all the arrays are the same length
        uint256 length = recipients.length;
        if (
            length < 1 || numbersToMint.length != length || presaleNumbersCanMint.length != length
                || proofs.length != length
        ) {
            revert InvalidBatchArguments();
        }

        // loop through and mint
        uint256 msgValue = msg.value;
        uint256 msgValueUsed = 0;
        for (uint256 i = 0; i < length; i++) {
            msgValueUsed =
                _purchase(nftAddress, recipients[i], numbersToMint[i], presaleNumbersCanMint[i], proofs[i], msgValue);
            msgValue -= msgValueUsed;
        }

        // refund any left over eth
        if (msgValue > 0) {
            _safeTransferETH(msg.sender, msgValue, wethAddress);
        }
    }

    /// @notice Internal function to purchase a token
    /// @dev Reverts on any of the following conditions
    ///     - Drop isn't active or configured
    ///     - numberToMint is 0
    ///     - Invalid merkle proof during the presale phase
    ///     - Insufficent protocol fee
    ///     - Insufficient funds
    ///     - Already minted the allowance for the recipient
    ///     - Receiver is a contract that doesn't implement proper receiving functions
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    /// @param msgValue The current balance of eth remaining in the call for use in this function
    /// @return msgValueUsed The amount of eth distributed in this function
    function _purchase(
        address nftAddress,
        address recipient,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] memory proof,
        uint256 msgValue
    ) internal returns (uint256 msgValueUsed) {
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
            bytes32 leaf = bytes32(abi.encode(recipient, presaleNumberCanMint));
            if (!MerkleProof.verify(proof, drop.presaleMerkleRoot, leaf)) revert NotOnAllowlist();
            numberCanMint = _getNumberCanMint(presaleNumberCanMint, numberMinted, drop.supply);
        } else if (dropPhase == DropPhase.PUBLIC_SALE) {
            numberCanMint = _getNumberCanMint(drop.allowance, numberMinted, drop.supply);
            cost = drop.publicCost;
        } else {
            revert YouShallNotMint();
        }
        if (numberCanMint == 0) revert AlreadyReachedMintAllowance();

        // adjust drop state
        _updateDropState(nftAddress, round, recipient, numberCanMint, drop);

        // settle funds
        msgValueUsed = _settleUp(numberCanMint, cost, msgValue, drop);

        // mint
        _mintToken(nftAddress, recipient, numberCanMint, drop);

        emit Purchase(
            msg.sender,
            nftAddress,
            recipient,
            drop.currencyAddress,
            numberCanMint,
            cost,
            drop.decayRate,
            dropPhase == DropPhase.PRESALE
        );

        return msgValueUsed;
    }

    /// @notice Function to update the state of the drop
    /// @param nftAddress The nft contract address
    /// @param round The drop round for number minted
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberCanMint The number of tokens to mint
    /// @param drop The Drop cached in memory
    function _updateDropState(
        address nftAddress,
        uint256 round,
        address recipient,
        uint256 numberCanMint,
        Drop memory drop
    ) internal {
        // velocity mint
        if (drop.dropType == DropType.VELOCITY) {
            uint256 durationAdjust = drop.decayRate < 0
                ? uint256(-1 * drop.decayRate) * numberCanMint
                : uint256(drop.decayRate) * numberCanMint;
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
        _drops[nftAddress].supply -= numberCanMint;
        _numberMinted[nftAddress][round][recipient] += numberCanMint;
    }

    /// @notice Internal function to distribute funds for a _purchase
    /// @param numberCanMint The number of tokens that can be minted
    /// @param cost The cost per token
    /// @param msgValue The starting msg value
    /// @param drop The drop
    /// @return msgValueUsed The msg value used in the call
    function _settleUp(uint256 numberCanMint, uint256 cost, uint256 msgValue, Drop memory drop)
        internal
        returns (uint256 msgValueUsed)
    {
        uint256 totalProtocolFee = numberCanMint * protocolFee;
        uint256 totalSale = numberCanMint * cost;
        if (drop.currencyAddress == address(0)) {
            uint256 totalCost = totalSale + totalProtocolFee;
            if (msgValue < totalCost) revert InsufficientFunds();
            _safeTransferETH(drop.payoutReceiver, totalSale, wethAddress);
            msgValueUsed = totalCost;
        } else {
            if (msgValue < totalProtocolFee) revert InsufficientFunds();
            _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
            msgValueUsed = totalProtocolFee;
        }
        _safeTransferETH(protocolFeeReceiver, totalProtocolFee, wethAddress);
        return msgValueUsed;
    }

    /// @notice Internal function to mint the token
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberCanMint The number of tokens to mint
    /// @param drop The drop cached in memory (not read from storage again)
    function _mintToken(address nftAddress, address recipient, uint256 numberCanMint, Drop memory drop) internal {
        uint256 uriCounter = drop.initialSupply - drop.supply;
        for (uint256 i = 0; i < numberCanMint; i++) {
            ERC721TL(nftAddress).externalMint(
                recipient, string(abi.encodePacked(drop.baseUri, "/", (uriCounter + i).toString()))
            );
        }
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
        address prevWethAddress = wethAddress;
        wethAddress = newWethAddress;

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
        return numberCanMint;
    }
}

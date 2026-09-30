// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable, Ownable2Step} from "@openzeppelin-contracts-5.6.1/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin-contracts-5.6.1/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {BitMaps} from "@openzeppelin-contracts-5.6.1/utils/structs/BitMaps.sol";
import {OwnableAccessControlUpgradeable} from "tl-creator-contracts-4.1.1/lib/OwnableAccessControlUpgradeable.sol";
import {IERC721TL} from "tl-creator-contracts-4.1.1/erc-721/IERC721TL.sol";
import {TransferHelper} from "./lib/TransferHelper.sol";
import {SanctionsCompliance} from "./lib/SanctionsCompliance.sol";
import {CurrencyAllowlist} from "./lib/CurrencyAllowlist.sol";
import {DropPhase, DropType, DropErrors} from "./utils/CommonUtils.sol";
import {Drop, ITLStacks721Events} from "./utils/TLStacks721Utils.sol";

/////////////////////////////////////////////////////////////////////
// TL STACKS 721
/////////////////////////////////////////////////////////////////////

/// @title TLStacks721
/// @notice Transient Labs mint contract for ERC721TL-based contracts
/// @author Transient Labs, Inc.
/// @custom:version-last-updated 2.8.0
contract TLStacks721 is
    Ownable2Step,
    Pausable,
    ReentrancyGuard,
    TransferHelper,
    SanctionsCompliance,
    CurrencyAllowlist,
    ITLStacks721Events,
    DropErrors
{
    /////////////////////////////////////////////////////////////////////
    // CONSTANTS
    /////////////////////////////////////////////////////////////////////

    using Strings for uint256;
    using BitMaps for BitMaps.BitMap;

    string public constant VERSION = "2.8.0";
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant APPROVED_MINT_CONTRACT = keccak256("APPROVED_MINT_CONTRACT");
    uint256 public constant BASIS = 10_000;
    uint256 public constant MAX_SELLER_FEE_BPS = 500; // 5% max seller fee

    /////////////////////////////////////////////////////////////////////
    // STORAGE
    /////////////////////////////////////////////////////////////////////

    address public protocolFeeReceiver; // the payout receiver for the protocol fee
    uint256 public protocolFee; // the protocol fee, in eth, to charge the buyer per token on ETH drops
    uint256 public ethSellerFeeBps; // the seller fee, in basis points, taken from the sale on ETH drops
    uint256 public erc20SellerFeeBps; // the seller fee, in basis points, taken from the sale on ERC-20 drops
    mapping(address nftAddress => Drop) internal _drops; // nft address -> Drop
    mapping(address nftAddress => mapping(uint256 round => mapping(address user => mapping(DropPhase => uint256))))
        internal _numberMinted; // nft address -> round -> user -> phase -> number minted
    mapping(address nftAddress => uint256) internal _rounds; // nft address -> round
    mapping(address nftAddress => mapping(uint256 round => bool)) internal _sellerFeeWaived; // nft address -> round -> seller fee waived
    mapping(address nftAddress => mapping(uint256 round => BitMaps.BitMap)) internal _mintedIndices; // nft address -> round -> minted indices for selectable drops

    /////////////////////////////////////////////////////////////////////
    // CONSTRUCTOR
    /////////////////////////////////////////////////////////////////////

    constructor(
        address initOwner,
        address initSanctionsOracle,
        address initProtocolFeeReceiver,
        uint256 initProtocolFee,
        uint256 initEthSellerFeeBps,
        uint256 initErc20SellerFeeBps
    ) Ownable(initOwner) Pausable() ReentrancyGuard() SanctionsCompliance(initSanctionsOracle) {
        _setProtocolFeeSettings(initProtocolFeeReceiver, initProtocolFee, initEthSellerFeeBps, initErc20SellerFeeBps);
    }

    /////////////////////////////////////////////////////////////////////
    // OWNER FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to set the protocol fee settings
    /// @dev Requires owner
    /// @param newProtocolFeeReceiver The new protocol fee receiver
    /// @param newProtocolFee The new protocol fee in ETH, charged to the buyer per token on ETH drops
    /// @param newEthSellerFeeBps The new seller fee in basis points for ETH drops
    /// @param newErc20SellerFeeBps The new seller fee in basis points for ERC-20 drops
    function setProtocolFeeSettings(
        address newProtocolFeeReceiver,
        uint256 newProtocolFee,
        uint256 newEthSellerFeeBps,
        uint256 newErc20SellerFeeBps
    ) external onlyOwner {
        _setProtocolFeeSettings(newProtocolFeeReceiver, newProtocolFee, newEthSellerFeeBps, newErc20SellerFeeBps);
    }

    /// @notice Function to waive the seller fee for the current round of a drop
    /// @dev Requires owner
    /// @dev Can be called before the drop is configured, and a waived seller fee stays waived for the round. The
    ///      waiver resets when the drop is closed or reconfigured, since that starts a new round.
    /// @param nftAddress The nft contract address
    function waiveSellerFee(address nftAddress) external onlyOwner {
        uint256 round = _rounds[nftAddress];
        _sellerFeeWaived[nftAddress][round] = true;

        emit SellerFeeWaived(nftAddress, round);
    }

    /// @notice Function to set the sanctions oracle
    /// @dev Requires owner
    /// @param newOracle The new oracle address
    function setSanctionsOracle(address newOracle) external onlyOwner {
        _updateSanctionsOracle(newOracle);
    }

    /// @notice Function to add or remove an ERC-20 currency from the allowlist
    /// @dev Requires owner
    /// @dev Removing a currency only blocks new sales from using it, existing sales are unaffected
    /// @param currencyAddress The ERC-20 currency address
    /// @param allowed Boolean indicating if the currency is allowed
    function setCurrencyAllowed(address currencyAddress, bool allowed) external onlyOwner {
        _setCurrencyAllowed(currencyAddress, allowed);
    }

    /// @notice Function to withdraw funds in case any are sent to this address on accident
    /// @dev Since this contract doesn't escrow funds, this is a safe addition
    /// @dev Requires owner
    /// @param currencyAddress The currency address to withdraw for
    /// @param amount The amount to transfer in base units
    function withdrawFunds(address currencyAddress, uint256 amount) external onlyOwner {
        if (currencyAddress == address(0)) {
            _safeTransferETH(msg.sender, amount);
        } else {
            _safeTransferERC20(msg.sender, currencyAddress, amount);
        }
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

    /////////////////////////////////////////////////////////////////////
    // DROP CONFIGURATION FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to configure a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract
    /// @dev Reverts if
    ///     - the payout receiver is the zero address or sanctioned
    ///     - the `dropType` is `NOT_CONFIGURED`
    ///     - the currency is not on the allowlist (native currency is always allowed)
    ///     - a drop is already configured and live
    ///     - the `intialSupply` does not equal the `supply`
    ///     - the `decayRate` is non-zero and there is a presale configured
    /// @dev For `SELECTABLE` drops, buyers pick which indices (0 to `initialSupply - 1`) they mint with `purchaseSelected`
    /// @param nftAddress The nft contract address
    /// @param drop The drop to configure
    function configureDrop(address nftAddress, Drop calldata drop) external nonReentrant whenNotPaused {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        if (!_isApprovedMintContract(nftAddress)) revert NotApprovedMintContract();
        if (!_checkPayoutReceiver(drop.payoutReceiver)) revert InvalidPayoutReceiver();
        if (!_isCurrencyAllowed(drop.currencyAddress)) revert CurrencyNotAllowed();
        if (drop.initialSupply != drop.supply) revert InvalidDropSupply();
        if (drop.dropType == DropType.NOT_CONFIGURED) revert InvalidDropType();
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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @param nftAddress The nft contract address
    /// @param payoutReceiver The recipient of the funds from the mint
    function updateDropPayoutReceiver(address nftAddress, address payoutReceiver) external nonReentrant whenNotPaused {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @param nftAddress The nft contract address
    /// @param allowance The number of tokens each wallet can mint during the public phase (separate from presale mints)
    function updateDropAllowance(address nftAddress, uint256 allowance) external nonReentrant whenNotPaused {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @dev The currency must be on the allowlist. Buyers are protected from changes made while their purchase is
    ///      pending by the `currencyAddress` and `maxCostPerToken` arguments of `purchase`.
    /// @param nftAddress The nft contract address
    /// @param currencyAddress The currency address (zero address represents ETH)
    /// @param presaleCost The cost of each token during the presale phase
    /// @param publicCost The cost of each token during the public phase
    function updateDropPrices(address nftAddress, address currencyAddress, uint256 presaleCost, uint256 publicCost)
        external
        nonReentrant
        whenNotPaused
    {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (!_isCurrencyAllowed(currencyAddress)) revert CurrencyNotAllowed();

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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @param nftAddress The nft contract address
    /// @param startTime The timestamp at which the drop starts
    /// @param presaleDuration The duration of the presale phase of the drop, in seconds
    /// @param publicDuration The duration of the public phase
    function updateDropDuration(address nftAddress, uint256 startTime, uint256 presaleDuration, uint256 publicDuration)
        external
        nonReentrant
        whenNotPaused
    {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @param nftAddress The nft contract address
    /// @param presaleMerkleRoot The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropPresaleMerkleRoot(address nftAddress, bytes32 presaleMerkleRoot)
        external
        nonReentrant
        whenNotPaused
    {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

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
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @param nftAddress The nft contract address
    /// @param decayRate The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)
    function updateDropDecayRate(address nftAddress, int256 decayRate) external nonReentrant whenNotPaused {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

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

    /// @notice Function to decrease the total supply of a drop
    /// @dev Caller must be the nft contract owner or an admin on the contract, and cannot be sanctioned
    /// @dev The new total supply is set rather than the remaining supply, so purchases landing before this
    ///      transaction can't change the final total. Setting it to the number already minted ends the drop.
    /// @dev The token uri counter (`initialSupply - supply`) is unchanged, so later mints continue in order
    /// @dev Not allowed for selectable drops, since already minted indices could fall outside the new range. Use
    ///      `closeDrop` to end a selectable drop early.
    /// @param nftAddress The nft contract address
    /// @param newInitialSupply The new total supply of the drop (between the number minted and the current total)
    function updateDropSupply(address nftAddress, uint256 newInitialSupply) external nonReentrant whenNotPaused {
        // sanctions
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();

        // check pre-conditions
        if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();
        Drop memory drop = _drops[nftAddress];
        DropPhase mPhase = _getDropPhase(drop);
        if (mPhase == DropPhase.NOT_CONFIGURED || mPhase == DropPhase.ENDED) revert DropUpdateNotAllowed();
        if (drop.dropType == DropType.SELECTABLE) revert NotAllowedForSelectableDrops();
        uint256 numberMinted = drop.initialSupply - drop.supply;
        if (newInitialSupply > drop.initialSupply || newInitialSupply < numberMinted) revert InvalidDropSupply();

        // update supply
        drop.initialSupply = newInitialSupply;
        drop.supply = newInitialSupply - numberMinted;
        _drops[nftAddress].initialSupply = drop.initialSupply;
        _drops[nftAddress].supply = drop.supply;

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

    /////////////////////////////////////////////////////////////////////
    // PURCHASE FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to purchase tokens on a drop
    /// @dev The recipient's phase allowance is consumed even when another account pays. This intentionally supports
    ///      permissionless delegation and gifting, but an eligible payer can consume the allowance by minting to them.
    /// @dev Reverts on any of the following conditions
    ///     - Drop isn't active or configured
    ///     - numberToMint is 0
    ///     - Invalid merkle proof during the presale phase
    ///     - Incorrect ETH sent (price plus protocol fee for ETH drops, zero for ERC-20 drops)
    ///     - Insufficient ERC-20 funds or allowance
    ///     - Already minted the allowance for the recipient in the current phase (the presale merkle leaf during
    ///       presale, or `allowance` during the public sale, which are tracked separately)
    ///     - The drop currency doesn't match `currencyAddress`
    ///     - The current cost per token is greater than `maxCostPerToken`
    ///     - The drop round doesn't match `expectedRound`, so a drop that is closed and reconfigured (e.g. with a new
    ///       base uri) can't be minted with a transaction signed against the previous drop
    ///     - The drop is a selectable drop (use `purchaseSelected` instead)
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    /// @param currencyAddress The currency the buyer expects to pay in (zero address represents ETH)
    /// @param maxCostPerToken The maximum cost per token the buyer is willing to pay (excluding protocol fee)
    /// @param expectedRound The drop round the buyer expects to mint from
    function purchase(
        address nftAddress,
        address recipient,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] calldata proof,
        address currencyAddress,
        uint256 maxCostPerToken,
        uint256 expectedRound
    ) external payable nonReentrant whenNotPaused {
        (Drop memory drop, DropPhase dropPhase, uint256 cost) = _validatePurchase(
            nftAddress, recipient, numberToMint, presaleNumberCanMint, proof, expectedRound
        );

        // selectable drops can only be minted with `purchaseSelected`
        if (drop.dropType == DropType.SELECTABLE) revert NotAllowedForSelectableDrops();

        // protect the buyer from drop changes between signing and execution
        if (drop.currencyAddress != currencyAddress) revert CurrencyMismatch();
        if (cost > maxCostPerToken) revert PriceTooHigh();

        // adjust drop state
        _updateDropState(nftAddress, expectedRound, recipient, dropPhase, numberToMint, drop);

        // settle funds
        _settleUp(nftAddress, expectedRound, numberToMint, cost, drop);

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
    }

    /// @notice Function to purchase selected tokens on a selectable drop
    /// @dev The selected indices are the metadata indices (`baseUri/<index>`), not token ids. Token ids are still
    ///      assigned in order by the nft contract.
    /// @dev Selected indices are public calldata and are not reserved before inclusion. Another eligible buyer can mint
    ///      an observed index first, causing this transaction to revert.
    /// @dev The recipient's phase allowance is consumed even when another account pays. This intentionally supports
    ///      permissionless delegation and gifting, but an eligible payer can consume the allowance by minting to them.
    /// @dev Reverts on the same conditions as `purchase`, where the number to mint is the number of indices, and if
    ///     - The drop is not a selectable drop
    ///     - Any index is greater than or equal to the drop's `initialSupply`
    ///     - Any index has already been minted this round, or is repeated in `indices`
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param indices The 0-based indices of the pieces to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    /// @param currencyAddress The currency the buyer expects to pay in (zero address represents ETH)
    /// @param maxCostPerToken The maximum cost per token the buyer is willing to pay (excluding protocol fee)
    /// @param expectedRound The drop round the buyer expects to mint from
    function purchaseSelected(
        address nftAddress,
        address recipient,
        uint256[] calldata indices,
        uint256 presaleNumberCanMint,
        bytes32[] calldata proof,
        address currencyAddress,
        uint256 maxCostPerToken,
        uint256 expectedRound
    ) external payable nonReentrant whenNotPaused {
        (Drop memory drop, DropPhase dropPhase, uint256 cost) = _validatePurchase(
            nftAddress, recipient, indices.length, presaleNumberCanMint, proof, expectedRound
        );

        if (drop.dropType != DropType.SELECTABLE) revert NotSelectableDrop();

        // protect the buyer from drop changes between signing and execution
        if (drop.currencyAddress != currencyAddress) revert CurrencyMismatch();
        if (cost > maxCostPerToken) revert PriceTooHigh();

        // adjust drop state
        _markIndicesMinted(nftAddress, expectedRound, indices, drop.initialSupply);
        _updateDropState(nftAddress, expectedRound, recipient, dropPhase, indices.length, drop);

        // settle funds
        _settleUp(nftAddress, expectedRound, indices.length, cost, drop);

        // mint
        _mintSelectedTokens(nftAddress, recipient, indices, drop.baseUri);

        emit Purchase(
            nftAddress,
            recipient,
            drop.currencyAddress,
            indices.length,
            cost,
            drop.decayRate,
            dropPhase == DropPhase.PRESALE
        );
        emit IndicesMinted(nftAddress, expectedRound, recipient, indices);
    }

    /////////////////////////////////////////////////////////////////////
    // EXTERNAL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Function to get a drop
    /// @param nftAddress The nft contract address
    /// @return Drop The drop for the nft contract and token id
    function getDrop(address nftAddress) external view returns (Drop memory) {
        return _drops[nftAddress];
    }

    /// @notice Function to get number minted on a drop for an address, in each phase
    /// @param nftAddress The nft contract address
    /// @param recipient The recipient of the nft
    /// @return presaleNumberMinted The number of tokens minted during the presale
    /// @return publicNumberMinted The number of tokens minted during the public sale
    function getNumberMinted(address nftAddress, address recipient)
        external
        view
        returns (uint256 presaleNumberMinted, uint256 publicNumberMinted)
    {
        uint256 round = _rounds[nftAddress];
        presaleNumberMinted = _numberMinted[nftAddress][round][recipient][DropPhase.PRESALE];
        publicNumberMinted = _numberMinted[nftAddress][round][recipient][DropPhase.PUBLIC_SALE];
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

    /// @notice Function to check if the seller fee is waived for the current round of a drop
    /// @param nftAddress The nft contract address
    /// @return bool Boolean indicating if the seller fee is waived
    function isSellerFeeWaived(address nftAddress) external view returns (bool) {
        return _sellerFeeWaived[nftAddress][_rounds[nftAddress]];
    }

    /// @notice Function to check if an index has been minted in the current round of a selectable drop
    /// @param nftAddress The nft contract address
    /// @param index The 0-based index of the piece
    /// @return bool Boolean indicating if the index has been minted
    function isIndexMinted(address nftAddress, uint256 index) external view returns (bool) {
        return _mintedIndices[nftAddress][_rounds[nftAddress]].get(index);
    }

    /// @notice Function to get the minted indices in the current round of a selectable drop, as bitmap words
    /// @dev Bit `i` of `words[w]` represents index `w * 256 + i`, so index `index` is bit `index % 256` of
    ///      `words[index >> 8]`. Returns one word per 256 indices of the drop's `initialSupply`.
    /// @param nftAddress The nft contract address
    /// @return words The bitmap words of minted indices for the drop
    function getMintedIndices(address nftAddress) external view returns (uint256[] memory words) {
        BitMaps.BitMap storage mintedIndices = _mintedIndices[nftAddress][_rounds[nftAddress]];
        uint256 numWords = (_drops[nftAddress].initialSupply + 255) >> 8;
        words = new uint256[](numWords);
        for (uint256 w = 0; w < numWords; w++) {
            // BitMaps doesn't expose whole words, so read its backing mapping directly
            words[w] = mintedIndices._data[w];
        }
    }

    /////////////////////////////////////////////////////////////////////
    // INTERNAL HELPER FUNCTIONS
    /////////////////////////////////////////////////////////////////////

    /// @notice Internal function to set the protocol fee settings
    /// @dev The receiver can only be the zero address if all fees are zero, so fees are never burned
    /// @dev The receiver cannot be sanctioned. This isn't re-checked on purchase, since the receiver is owner controlled.
    /// @dev Seller fees cannot exceed `MAX_SELLER_FEE_BPS`
    /// @param newProtocolFeeReceiver The new protocol fee receiver
    /// @param newProtocolFee The new protocol fee in ETH, charged to the buyer per token on ETH drops
    /// @param newEthSellerFeeBps The new seller fee in basis points for ETH drops
    /// @param newErc20SellerFeeBps The new seller fee in basis points for ERC-20 drops
    function _setProtocolFeeSettings(
        address newProtocolFeeReceiver,
        uint256 newProtocolFee,
        uint256 newEthSellerFeeBps,
        uint256 newErc20SellerFeeBps
    ) internal {
        if (
            newProtocolFeeReceiver == address(0)
                && (newProtocolFee != 0 || newEthSellerFeeBps != 0 || newErc20SellerFeeBps != 0)
        ) revert InvalidProtocolFeeReceiver();
        if (_isSanctioned(newProtocolFeeReceiver)) revert InvalidProtocolFeeReceiver();
        if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) {
            revert InvalidSellerFeeBps();
        }

        protocolFeeReceiver = newProtocolFeeReceiver;
        protocolFee = newProtocolFee;
        ethSellerFeeBps = newEthSellerFeeBps;
        erc20SellerFeeBps = newErc20SellerFeeBps;

        emit ProtocolFeeUpdated(newProtocolFeeReceiver, newProtocolFee, newEthSellerFeeBps, newErc20SellerFeeBps);
    }

    /// @notice Internal function to check if msg.sender is the owner or an admin on the contract
    /// @param nftAddress The nft contract address
    /// @return bool Boolean indicating if msg.sender is the owner or an admin on the nft contract
    function _isDropAdmin(address nftAddress) internal view returns (bool) {
        return (msg.sender == OwnableAccessControlUpgradeable(nftAddress).owner()
                || OwnableAccessControlUpgradeable(nftAddress).hasRole(ADMIN_ROLE, msg.sender));
    }

    /// @notice Intenral function to check if this contract is an approved mint contract
    /// @param nftAddress The nft contract address
    /// @return bool Boolean indicating if this contract is approved or not
    function _isApprovedMintContract(address nftAddress) internal view returns (bool) {
        return OwnableAccessControlUpgradeable(nftAddress).hasRole(APPROVED_MINT_CONTRACT, address(this));
    }

    /// @notice Internal function to check if a payout address is a valid address
    /// @param payoutReceiver The payout address to check
    /// @return bool Indication of if the payout address is not the zero address and not sanctioned
    function _checkPayoutReceiver(address payoutReceiver) internal view returns (bool) {
        return payoutReceiver != address(0) && !_isSanctioned(payoutReceiver);
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

    /// @notice Internal function to run the purchase checks shared by `purchase` and `purchaseSelected`
    /// @dev Checks sanctions, the drop round, the drop phase, the presale merkle proof, and the mint allowance
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft
    /// @param numberToMint The number of tokens to mint
    /// @param presaleNumberCanMint The number of tokens the recipient can mint during presale
    /// @param proof The merkle proof for the presale page
    /// @param expectedRound The drop round the buyer expects to mint from
    /// @return drop The drop cached in memory
    /// @return dropPhase The current drop phase
    /// @return cost The cost per token for the current drop phase
    function _validatePurchase(
        address nftAddress,
        address recipient,
        uint256 numberToMint,
        uint256 presaleNumberCanMint,
        bytes32[] calldata proof,
        uint256 expectedRound
    ) internal view returns (Drop memory drop, DropPhase dropPhase, uint256 cost) {
        if (_isSanctioned(msg.sender)) revert SanctionedAddress();
        if (_isSanctioned(recipient)) revert SanctionedAddress();

        // cache drop
        drop = _drops[nftAddress];
        dropPhase = _getDropPhase(drop);

        // don't send funds to a payout receiver that has been sanctioned since the drop was configured
        if (_isSanctioned(drop.payoutReceiver)) revert SanctionedAddress();

        // protect the buyer from the drop being closed and reconfigured between signing and execution
        // after this check, `expectedRound` is the current round
        if (_rounds[nftAddress] != expectedRound) revert DropRoundChanged();

        cost = drop.presaleCost;

        // pre-conditions - revert for safety and expected behavior from users - UX for batch purchases needs to be smart in order to avoid reverting conditions
        if (numberToMint == 0) revert MintZeroTokens();
        uint256 numberMinted = _numberMinted[nftAddress][expectedRound][recipient][dropPhase];
        uint256 numberCanMint;
        if (dropPhase == DropPhase.PRESALE) {
            bytes32 hashedRecipient = keccak256(abi.encode(recipient));
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(hashedRecipient, presaleNumberCanMint)))); // double hash to prevent second preimage attack: https://github.com/@openzeppelin-contracts-5.6.1/@openzeppelin-contracts-5.6.1-contracts/issues/3091
            if (!MerkleProof.verify(proof, drop.presaleMerkleRoot, leaf)) revert NotOnAllowlist();
            numberCanMint = _getNumberCanMint(presaleNumberCanMint, numberMinted, drop.supply);
        } else if (dropPhase == DropPhase.PUBLIC_SALE) {
            numberCanMint = _getNumberCanMint(drop.allowance, numberMinted, drop.supply);
            cost = drop.publicCost;
        } else {
            revert YouShallNotMint();
        }

        // revert if minting more than allowed
        if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();
    }

    /// @notice Internal function to mark indices as minted on a selectable drop
    /// @dev Reverts if an index is out of range or already minted, which also catches repeated indices
    /// @param nftAddress The nft contract address
    /// @param round The drop round
    /// @param indices The 0-based indices to mark as minted
    /// @param initialSupply The drop initial supply, which bounds the indices
    function _markIndicesMinted(address nftAddress, uint256 round, uint256[] calldata indices, uint256 initialSupply)
        internal
    {
        BitMaps.BitMap storage mintedIndices = _mintedIndices[nftAddress][round];
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];
            if (index >= initialSupply) revert IndexOutOfRange();
            if (mintedIndices.get(index)) revert IndexAlreadyMinted();
            mintedIndices.set(index);
        }
    }

    /// @notice Function to update the state of the drop
    /// @param nftAddress The nft contract address
    /// @param round The drop round for number minted
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param phase The drop phase the tokens are minted in
    /// @param numberToMint The number of tokens to mint
    /// @param drop The Drop cached in memory
    function _updateDropState(
        address nftAddress,
        uint256 round,
        address recipient,
        DropPhase phase,
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
        _numberMinted[nftAddress][round][recipient][phase] += numberToMint;
    }

    /// @notice Internal function to distribute funds for a _purchase
    /// @param nftAddress The nft contract address
    /// @param round The drop round, used to check if the seller fee is waived
    /// @param numberToMint The number of tokens that can be minted
    /// @param cost The cost per token
    /// @param drop The drop
    function _settleUp(address nftAddress, uint256 round, uint256 numberToMint, uint256 cost, Drop memory drop)
        internal
    {
        uint256 totalSale = numberToMint * cost;
        bool isEth = drop.currencyAddress == address(0);

        // calculate the seller fee (rounds down in favor of the seller)
        uint256 sellerFee;
        if (!_sellerFeeWaived[nftAddress][round]) {
            sellerFee = totalSale * (isEth ? ethSellerFeeBps : erc20SellerFeeBps) / BASIS;
        }
        uint256 sellerProceeds = totalSale - sellerFee;

        // payout the mint and protocol fees
        if (isEth) {
            uint256 totalProtocolFee = numberToMint * protocolFee;
            if (msg.value != totalSale + totalProtocolFee) revert IncorrectFunds();
            _safeTransferETH(drop.payoutReceiver, sellerProceeds);
            _safeTransferETH(protocolFeeReceiver, totalProtocolFee + sellerFee);
        } else {
            if (msg.value != 0) revert IncorrectFunds();
            _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, sellerProceeds);
            _safeTransferFromERC20(msg.sender, protocolFeeReceiver, drop.currencyAddress, sellerFee);
        }
    }

    /// @notice Internal function to mint the token
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param numberToMint The number of tokens to mint
    /// @param drop The drop cached in memory (not read from storage again)
    function _mintToken(address nftAddress, address recipient, uint256 numberToMint, Drop memory drop) internal {
        uint256 uriCounter = drop.initialSupply - drop.supply;
        for (uint256 i = 0; i < numberToMint; i++) {
            IERC721TL(nftAddress)
                .externalMint(recipient, string(abi.encodePacked(drop.baseUri, "/", (uriCounter + i).toString())));
        }
    }

    /// @notice Internal function to mint selected tokens on a selectable drop
    /// @param nftAddress The nft contract address
    /// @param recipient The receiver of the nft (msg.sender is the payer but this allows delegation)
    /// @param indices The 0-based indices to mint
    /// @param baseUri The drop base uri
    function _mintSelectedTokens(
        address nftAddress,
        address recipient,
        uint256[] calldata indices,
        string memory baseUri
    ) internal {
        for (uint256 i = 0; i < indices.length; i++) {
            IERC721TL(nftAddress).externalMint(recipient, string(abi.encodePacked(baseUri, "/", indices[i].toString())));
        }
    }
}

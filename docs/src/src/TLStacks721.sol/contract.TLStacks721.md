# TLStacks721
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/TLStacks721.sol)

**Inherits:**
Ownable, Pausable, ReentrancyGuard, TransferHelper, SanctionsCompliance, [ITLStacks721Events](/src/utils/TLStacks721Utils.sol/interface.ITLStacks721Events.md), [DropErrors](/src/utils/CommonUtils.sol/interface.DropErrors.md)

**Author:**
transientlabs.xyz

Transient Labs Stacks mint contract for ERC721TL-based contracts


## State Variables
### VERSION

```solidity
string public constant VERSION = "2.0.0";
```


### ADMIN_ROLE

```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```


### APPROVED_MINT_CONTRACT

```solidity
bytes32 public constant APPROVED_MINT_CONTRACT = keccak256("APPROVED_MINT_CONTRACT");
```


### protocolFeeReceiver

```solidity
address public protocolFeeReceiver;
```


### protocolFee

```solidity
uint256 public protocolFee;
```


### weth

```solidity
address public weth;
```


### _drops

```solidity
mapping(address => Drop) internal _drops;
```


### _numberMinted

```solidity
mapping(address => mapping(uint256 => mapping(address => uint256))) internal _numberMinted;
```


### _rounds

```solidity
mapping(address => uint256) internal _rounds;
```


## Functions
### constructor


```solidity
constructor(
    address initSanctionsOracle,
    address initWethAddress,
    address initProtocolFeeReceiver,
    uint256 initProtocolFee
) Ownable Pausable ReentrancyGuard SanctionsCompliance(initSanctionsOracle);
```

### setWethAddress

Function to set a new weth address

*Requires owner*


```solidity
function setWethAddress(address newWethAddress) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newWethAddress`|`address`|The new weth address|


### setProtocolFeeSettings

Function to set the protocol fee settings

*Requires owner*


```solidity
function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFee) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newProtocolFeeReceiver`|`address`|The new protocol fee receiver|
|`newProtocolFee`|`uint256`|The new protocol fee in ETH|


### pause

Function to pause the contract

*Requires owner*


```solidity
function pause(bool status) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`status`|`bool`|The boolean to set the internal pause variable|


### setSanctionsOracle

Function to set the sanctions oracle

*Requires owner*


```solidity
function setSanctionsOracle(address newOracle) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOracle`|`address`|The new oracle address|


### configureDrop

Function to configure a drop

*Caller must be the nft contract owner or an admin on the contract*

*Reverts if
- the payout receiver is the zero address
- a drop is already configured
- the `intiialSupply` does not equal the `supply`
- the `decayRate` is non-zero and there is a presale configured*


```solidity
function configureDrop(address nftAddress, Drop calldata drop) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`drop`|`Drop`|The drop to configure|


### updateDropPayoutReceiver

Function to update the payout receiver of a drop

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropPayoutReceiver(address nftAddress, address payoutReceiver) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`payoutReceiver`|`address`|The recipient of the funds from the mint|


### updateDropAllowance

Function to update the drop public allowance

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropAllowance(address nftAddress, uint256 allowance) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`allowance`|`uint256`|The number of tokens allowed to be minted per wallet during the public phase of the drop|


### updateDropPrices

Function to update the drop prices and currency

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropPrices(address nftAddress, address currencyAddress, uint256 presaleCost, uint256 publicCost)
    external
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`currencyAddress`|`address`|The currency address (zero address represents ETH)|
|`presaleCost`|`uint256`|The cost of each token during the presale phase|
|`publicCost`|`uint256`|The cost of each token during the presale phase|


### updateDropDuration

Function to adjust drop durations

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropDuration(address nftAddress, uint256 startTime, uint256 presaleDuration, uint256 publicDuration)
    external
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`startTime`|`uint256`|The timestamp at which the drop starts|
|`presaleDuration`|`uint256`|The duration of the presale phase of the drop, in seconds|
|`publicDuration`|`uint256`|The duration of the public phase|


### updateDropPresaleMerkleRoot

Function to alter a drop merkle root

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropPresaleMerkleRoot(address nftAddress, bytes32 presaleMerkleRoot) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`presaleMerkleRoot`|`bytes32`|The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)|


### updateDropDecayRate

Function to adjust the drop decay rate

*Caller must be the nft contract owner or an admin on the contract*


```solidity
function updateDropDecayRate(address nftAddress, int256 decayRate) external whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`decayRate`|`int256`|The merkle root for the presale phase (each leaf is abi encoded with the recipient and number they can mint during presale)|


### closeDrop


```solidity
function closeDrop(address nftAddress) external;
```

### purchase

Function to purchase tokens on a drop

*Reverts on any of the following conditions
- Drop isn't active or configured
- numberToMint is 0
- Invalid merkle proof during the presale phase
- Insufficent protocol fee
- Insufficient funds
- Already minted the allowance for the recipient*


```solidity
function purchase(
    address nftAddress,
    address recipient,
    uint256 numberToMint,
    uint256 presaleNumberCanMint,
    bytes32[] calldata proof
) external payable whenNotPaused nonReentrant returns (uint256 refundAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`recipient`|`address`|The receiver of the nft (msg.sender is the payer but this allows delegation)|
|`numberToMint`|`uint256`|The number of tokens to mint|
|`presaleNumberCanMint`|`uint256`|The number of tokens the recipient can mint during presale|
|`proof`|`bytes32[]`|The merkle proof for the presale page|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`refundAmount`|`uint256`|The amount of eth refunded to the caller|


### _updateDropState

Function to update the state of the drop


```solidity
function _updateDropState(address nftAddress, uint256 round, address recipient, uint256 numberToMint, Drop memory drop)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`round`|`uint256`|The drop round for number minted|
|`recipient`|`address`|The receiver of the nft (msg.sender is the payer but this allows delegation)|
|`numberToMint`|`uint256`|The number of tokens to mint|
|`drop`|`Drop`|The Drop cached in memory|


### _settleUp

Internal function to distribute funds for a _purchase


```solidity
function _settleUp(uint256 numberToMint, uint256 cost, Drop memory drop) internal returns (uint256 refundAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`numberToMint`|`uint256`|The number of tokens that can be minted|
|`cost`|`uint256`|The cost per token|
|`drop`|`Drop`|The drop|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`refundAmount`|`uint256`|The amount of eth refunded to msg.sender|


### _mintToken

Internal function to mint the token


```solidity
function _mintToken(address nftAddress, address recipient, uint256 numberToMint, Drop memory drop) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`recipient`|`address`|The receiver of the nft (msg.sender is the payer but this allows delegation)|
|`numberToMint`|`uint256`|The number of tokens to mint|
|`drop`|`Drop`|The drop cached in memory (not read from storage again)|


### getDrop

Function to get a drop


```solidity
function getDrop(address nftAddress) external view returns (Drop memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Drop`|Drop The drop for the nft contract and token id|


### getNumberMinted

Function to get number minted on a drop for an address


```solidity
function getNumberMinted(address nftAddress, address recipient) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`recipient`|`address`|The recipient of the nft|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The number of tokens minted|


### getDropPhase

Function to get the drop phase


```solidity
function getDropPhase(address nftAddress) external view returns (DropPhase);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`DropPhase`|DropPhase The drop phase|


### getDropRound

Function to get the drop round


```solidity
function getDropRound(address nftAddress) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The round for the drop based on the nft contract and token id|


### _setWethAddress

Internal function to set the weth address


```solidity
function _setWethAddress(address newWethAddress) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newWethAddress`|`address`|The new weth address|


### _setProtocolFeeSettings

Internal function to set the protocol fee settings


```solidity
function _setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFee) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newProtocolFeeReceiver`|`address`|The new protocol fee receiver|
|`newProtocolFee`|`uint256`|The new protocol fee in ETH|


### _isDropAdmin

Internal function to check if msg.sender is the owner or an admin on the contract


```solidity
function _isDropAdmin(address nftAddress) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Boolean indicating if msg.sender is the owner or an admin on the nft contract|


### _isApprovedMintContract

Intenral function to check if this contract is an approved mint contract


```solidity
function _isApprovedMintContract(address nftAddress) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Boolean indicating if this contract is approved or not|


### _checkPayoutReceiver

Internal function to check if a payout address is a valid address


```solidity
function _checkPayoutReceiver(address payoutReceiver) internal pure returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payoutReceiver`|`address`|The payout address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Indication of if the payout address is not the zero address|


### _getDropPhase

Internal function to get the drop phase


```solidity
function _getDropPhase(Drop memory drop) internal view returns (DropPhase);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`drop`|`Drop`|The drop in question|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`DropPhase`|DropPhase The drop phase enum value|


### _getNumberCanMint

Internal function to determine how many tokens can be minted by an address


```solidity
function _getNumberCanMint(uint256 allowance, uint256 numberMinted, uint256 supply)
    internal
    pure
    returns (uint256 numberCanMint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`allowance`|`uint256`|The amount allowed to mint|
|`numberMinted`|`uint256`|The amount already minted|
|`supply`|`uint256`|The drop supply|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`numberCanMint`|`uint256`|The number of tokens allowed to mint|



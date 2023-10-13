# TLAuctionHouse
[Git Source](https://github.com/Transient-Labs/tl-stacks/blob/50740a6194cf2cd3fb0343ae5849dbd8f751edf6/src/TLAuctionHouse.sol)

**Inherits:**
Ownable, Pausable, ReentrancyGuard, RoyaltyPayoutHelper, [ITLAuctionHouseEvents](/src/utils/TLAuctionHouseUtils.sol/interface.ITLAuctionHouseEvents.md), [AuctionHouseErrors](/src/utils/CommonUtils.sol/interface.AuctionHouseErrors.md)

**Author:**
transientlabs.xyz

Transient Labs Auction House with Reserve Auctions and Buy Now Sales for ERC-721 tokens


## State Variables
### VERSION

```solidity
string public constant VERSION = "2.0.0";
```


### EXTENSION_TIME

```solidity
uint256 public constant EXTENSION_TIME = 15 minutes;
```


### BASIS

```solidity
uint256 public constant BASIS = 10_000;
```


### protocolFeeReceiver

```solidity
address public protocolFeeReceiver;
```


### minBidIncreasePerc

```solidity
uint256 public minBidIncreasePerc;
```


### minBidIncreaseLimit

```solidity
uint256 public minBidIncreaseLimit;
```


### protocolFeePerc

```solidity
uint256 public protocolFeePerc;
```


### protocolFeeLimit

```solidity
uint256 public protocolFeeLimit;
```


### _auctions

```solidity
mapping(address => mapping(uint256 => Auction)) internal _auctions;
```


### _sales

```solidity
mapping(address => mapping(uint256 => Sale)) internal _sales;
```


## Functions
### constructor


```solidity
constructor(
    address initSanctionsOracle,
    address initWethAddress,
    address initRoyaltyEngineAddress,
    address initProtocolFeeReceiver,
    uint256 initMinBidIncreasePerc,
    uint256 initMinBidIncreaseLimit,
    uint256 initProtocolFeePerc,
    uint256 initProtocolFeeLimit
)
    Ownable
    Pausable
    ReentrancyGuard
    RoyaltyPayoutHelper(initSanctionsOracle, initWethAddress, initRoyaltyEngineAddress);
```

### setRoyaltyEngine

Function to set a new royalty engine address

*Requires owner*


```solidity
function setRoyaltyEngine(address newRoyaltyEngine) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRoyaltyEngine`|`address`|The new royalty engine address|


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


### setMinBidIncreaseSettings

Function to set the min bid increase settings

*Requires owner*


```solidity
function setMinBidIncreaseSettings(uint256 newMinBidIncreasePerc, uint256 newMinBidIncreaseLimit) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinBidIncreasePerc`|`uint256`|The new minimum bid increase nominal percentage, out of `BASIS`|
|`newMinBidIncreaseLimit`|`uint256`|The new minimum bid increase absolute limit|


### setProtocolFeeSettings

Function to set the protocol fee settings

*Requires owner*


```solidity
function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFeePerc, uint256 newProtocolFeeLimit)
    external
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newProtocolFeeReceiver`|`address`|The new protocol fee receiver|
|`newProtocolFeePerc`|`uint256`|The new protocol fee percentage, out of `BASIS`|
|`newProtocolFeeLimit`|`uint256`|The new protocol fee limit|


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


### configureAuction

Function to configure an auction

*Requires the following items to be true
- contract is not paused
- the auction hasn't been configured yet for the current token owner
- msg.sender is the owner of the token
- auction house is approved for all
- payoutReceiver isn't the zero address*


```solidity
function configureAuction(
    address nftAddress,
    uint256 tokenId,
    address payoutReceiver,
    address currencyAddress,
    uint256 reservePrice,
    uint256 auctionOpenTime,
    uint256 duration,
    bool reserveAuction
) external whenNotPaused nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|
|`payoutReceiver`|`address`|The address that receives the payout from the auction|
|`currencyAddress`|`address`|The currency to use|
|`reservePrice`|`uint256`|The auction reserve price|
|`auctionOpenTime`|`uint256`|The time at which bidding is allowed|
|`duration`|`uint256`|The duration of the auction after it is started|
|`reserveAuction`|`bool`|A flag dictating if the auction is a reserve auction or regular scheduled auction|


### cancelAuction

Function to cancel an auction

*Requires the following to be true
- msg.sender to be the auction seller
- the auction cannot be started*


```solidity
function cancelAuction(address nftAddress, uint256 tokenId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|


### bid

Function to bid on an auction

*Requires the following to be true
- contract is not paused
- block.timestamp is greater than the auction open timestamp
- bid meets or exceeds the reserve price / min bid price
- msg.sender has attached enough eth/erc20 as specified by `amount`
- protocol fee has been supplied, if needed*


```solidity
function bid(address nftAddress, uint256 tokenId, uint256 amount) external payable whenNotPaused nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|
|`amount`|`uint256`|The amount to bid in the currency address set in the auction|


### settleAuction

Function to settle an auction

*Can be called by anyone*

*Requires the following to be true
- auction has been started
- auction has ended*


```solidity
function settleAuction(address nftAddress, uint256 tokenId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|


### configureSale

Function to configure a buy now sale

*Requires the following to be true
- contract is not paused
- the sale hasn't been configured yet by the current token owner
- an auction hasn't been started - this is captured by token ownership
- msg.sender is the owner of the token
- auction house is approved for all
- payoutReceiver isn't the zero address*


```solidity
function configureSale(
    address nftAddress,
    uint256 tokenId,
    address payoutReceiver,
    address currencyAddress,
    uint256 price,
    uint256 saleOpenTime
) external whenNotPaused nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|
|`payoutReceiver`|`address`|The address that receives the payout from the sale|
|`currencyAddress`|`address`|The currency to use|
|`price`|`uint256`|The sale price|
|`saleOpenTime`|`uint256`|The time at which the sale opens|


### cancelSale

Function to cancel a sale

*Requires msg.sender to be the token owner*


```solidity
function cancelSale(address nftAddress, uint256 tokenId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|


### buyNow

Function to buy a token

*Requires the following to be true
- contract is not paused
- block.timestamp is greater than the sale open timestamp
- msg.sender has attached enough eth/erc20 as specified by the sale
- protocol fee has been supplied, if needed*


```solidity
function buyNow(address nftAddress, uint256 tokenId) external payable whenNotPaused nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|


### getSale

function to get a sale


```solidity
function getSale(address nftAddress, uint256 tokenId) external view returns (Sale memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Sale`|sale The sale struct|


### getAuction

function to get an auction


```solidity
function getAuction(address nftAddress, uint256 tokenId) external view returns (Auction memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Auction`|auction The auction struct|


### calcNextMinBid

function to get the next minimum bid price for an auction


```solidity
function calcNextMinBid(address nftAddress, uint256 tokenId) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The nft token id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The next minimum bid required|


### calcProtocolFee

function to calculate the protocol fee


```solidity
function calcProtocolFee(uint256 amount) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The value to calculate the fee for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The calculated fee|


### _setMinBidIncreaseSettings

Internal function to set the min bid increase settings


```solidity
function _setMinBidIncreaseSettings(uint256 newMinBidIncreasePerc, uint256 newMinBidIncreaseLimit) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinBidIncreasePerc`|`uint256`|The new minimum bid increase nominal percentage, out of `BASIS`|
|`newMinBidIncreaseLimit`|`uint256`|The new minimum bid increase absolute limit|


### _setProtocolFeeSettings

Internal function to set the protocol fee settings


```solidity
function _setProtocolFeeSettings(
    address newProtocolFeeReceiver,
    uint256 newProtocolFeePerc,
    uint256 newProtocolFeeLimit
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newProtocolFeeReceiver`|`address`|The new protocol fee receiver|
|`newProtocolFeePerc`|`uint256`|The new protocol fee percentage, out of `BASIS`|
|`newProtocolFeeLimit`|`uint256`|The new protocol fee limit|


### _checkTokenOwnership

Internal function to check if a token is owned by an address


```solidity
function _checkTokenOwnership(IERC721 nft, uint256 tokenId, address potentialTokenOwner) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nft`|`IERC721`|The nft contract|
|`tokenId`|`uint256`|The nft token id|
|`potentialTokenOwner`|`address`|The potential token owner to check against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Indication of if the address in quesion is the owner of the token|


### _checkAuctionHouseApproval

Internal function to check if the auction house is approved for all


```solidity
function _checkAuctionHouseApproval(IERC721 nft, address seller) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nft`|`IERC721`|The nft contract|
|`seller`|`address`|The seller to check against|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Indication of if the auction house is approved for all by the seller|


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


### _calcNextMinBid

Internal function to calculate the next min bid price


```solidity
function _calcNextMinBid(uint256 currentBid) internal view returns (uint256 nextMinBid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currentBid`|`uint256`|The current bid|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nextMinBid`|`uint256`|The next minimum bid|


### _calcProtocolFee

Internal function to calculate the protocol fee


```solidity
function _calcProtocolFee(uint256 amount) internal view returns (uint256 fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The value of the sale|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|The protocol fee|


### _payout

Internal function to payout from the contract


```solidity
function _payout(address nftAddress, uint256 tokenId, address currencyAddress, uint256 amount, address payoutReceiver)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftAddress`|`address`|The nft contract address|
|`tokenId`|`uint256`|The token id|
|`currencyAddress`|`address`|The currency address (ZERO ADDRESS == ETH)|
|`amount`|`uint256`|The sale/auction end price|
|`payoutReceiver`|`address`|The receiver for the sale payout (what's remaining after royalties)|



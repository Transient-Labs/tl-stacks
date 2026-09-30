# Who can call what

Companion to [Trust Model and Protections](trust-model.md). Transient Labs Stacks 2.8.0.

65 state-changing functions: 8 callable by anyone, 29 limited to a stored role, 28 limited to an owner.

Inherited `Ownable` / `Ownable2Step` functions are included. They are not declared in `src/`, and they are callable on the deployed contracts. View and pure functions are omitted.

---

## Protocol Flow Paths

### Setup (Owner)

`constructor` → `setProtocolFeeSettings()` → `setCurrencyAllowed()` → `setSanctionsOracle()` → `transferOwnership()` → `acceptOwnership()`

Auction house also: `setCreatorLookup()` → `setRoyaltyLookup()`. `RoyaltyLookup`: `setRoyaltyEngine()`.

### Seller (auction)

`[owner allowlist above]` → `TLAuctionHouse.list()` / `batchList()`  ◄── caller is token owner; house must be approved

→ `updateListing()`  ◄── `highestBidder == address(0)`

→ `updatePayoutReceiver()`  ◄── any time before settlement or cancel

→ `delist()`  ◄── no bid; not pause-gated

### Buyer (auction)

`[list above]` → `bid()`  ◄── `openTime` reached; listing id and currency match

→ `topUpBid()`  ◄── caller is `highestBidder`; auction not ended

→ `buyNow()`  ◄── buy-now type; no bid yet; price ≤ `maxPrice`

→ `settleAuction()`  ◄── anyone, after `startTime + duration`

→ `cancelUnsettledAuction()`  ◄── seller or highest bidder, after end + 7 days

→ `claimFunds()` / `claimNft()`

### Drop admin

NFT grants `APPROVED_MINT_CONTRACT`; caller is the NFT `owner` or `ADMIN_ROLE`

→ `configureDrop()` → `updateDrop*()` → `closeDrop()`  ◄── `closeDrop` is not pause-gated

`waiveSellerFee()` is the stacks owner, not the drop admin.

### Buyer (mint)

`[configure above]` → `TLStacks721.purchase()` / `purchaseSelected()` or `TLStacks1155.purchase()`

◄── phase window open; presale merkle binds `recipient`; `expectedRound`, currency, and `maxCostPerToken` match storage

---

## Permissionless

### `TLAuctionHouse.bid()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, `nonReentrant`, `whenNotPaused` |
| Caller | Buyer |
| Parameters | `nftAddress`, `tokenId`, `currencyAddress`, `amount`, `expectedListingId` (user-controlled); `msg.value` (user-controlled) |
| Call chain | `→ TLAuctionHouse._escrowFunds() → TransferHelper._safeTransferFromERC20()` or ETH `msg.value` check; `→ TLAuctionHouse._payout() → TransferHelper._trySafeTransferETH()` / `_trySafeTransferERC20()` or `_credit()` |
| State modified | `_listings[nft][token].highestBid`, `highestBidder`, `recipient`, `startTime` (first reserve bid), `duration` (anti-snipe); `claimableFunds` if the previous payout is credited |
| Value flow | Buyer → auction house (`amount`); previous bidder ← auction house (`previousBid`) |
| Reentrancy guard | yes |

### `TLAuctionHouse.buyNow()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, `nonReentrant`, `whenNotPaused` |
| Caller | Buyer (private sales still deliver only to `listing.recipient`) |
| Parameters | `nftAddress`, `tokenId`, `recipient`, `currencyAddress`, `maxPrice`, `expectedListingId` (user-controlled) |
| Call chain | `→ TLAuctionHouse._escrowFunds() → TLAuctionHouse._completeSale() → CreatorLookup.getCreator() / RoyaltyLookup.getRoyalty() → TLAuctionHouse._transferNft() → TLAuctionHouse._payout()` |
| State modified | deletes `_listings[nft][token]`; may credit `claimableFunds` |
| Value flow | Buyer → auction house (`buyNowPrice`); house → protocol fee receiver, royalty recipients, `payoutReceiver` |
| Reentrancy guard | yes |

### `TLAuctionHouse.settleAuction()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant`, `whenNotPaused` |
| Caller | Anyone |
| Parameters | `nftAddress`, `tokenId` (user-controlled) |
| Call chain | `→ TLAuctionHouse._completeSale() → CreatorLookup.getCreator() / RoyaltyLookup.getRoyalty() → TLAuctionHouse._transferNft() → TLAuctionHouse._payout()` |
| State modified | deletes `_listings[nft][token]`; may credit `claimableFunds` |
| Value flow | Escrowed `highestBid` → protocol fee receiver, royalty recipients, `payoutReceiver`; NFT → `highestBidder` |
| Reentrancy guard | yes |

### `TLAuctionHouse.claimFunds()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `nonReentrant` |
| Caller | Account with a `claimableFunds` balance |
| Parameters | `currencyAddress`, `to` (user-controlled) |
| Call chain | `→ TransferHelper._safeTransferETH()` or `TransferHelper._safeTransferERC20()` |
| State modified | `claimableFunds[msg.sender][currency] = 0` |
| Value flow | Auction house → `to` |
| Reentrancy guard | yes |

### `TLStacks721.purchase()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, `nonReentrant`, `whenNotPaused` |
| Caller | Payer; may differ from `recipient`. The recipient receives the mint and consumes the phase allowance. |
| Parameters | `nftAddress`, `recipient`, `numberToMint`, `presaleNumberCanMint`, `proof`, `currencyAddress`, `maxCostPerToken`, `expectedRound` (user-controlled) |
| Call chain | `→ TLStacks721._validatePurchase() → TLStacks721._updateDropState() → TLStacks721._settleUp() → TransferHelper → TLStacks721._mintToken() → IERC721TL.externalMint()` |
| State modified | `_drops[nft].supply`, `publicDuration` (velocity), `_numberMinted[nft][round][recipient][phase]` |
| Value flow | Buyer → `drop.payoutReceiver` (seller proceeds) and `protocolFeeReceiver` (seller fee + ETH protocol fee) |
| Reentrancy guard | yes |

### `TLStacks721.purchaseSelected()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, `nonReentrant`, `whenNotPaused` |
| Caller | Payer; may differ from `recipient`. The recipient receives the mint and consumes the phase allowance. |
| Parameters | `nftAddress`, `recipient`, `indices`, `presaleNumberCanMint`, `proof`, `currencyAddress`, `maxCostPerToken`, `expectedRound` (user-controlled) |
| Ordering | Indices are public calldata and are not reserved before inclusion; an earlier successful purchase can take them. |
| Call chain | `→ TLStacks721._validatePurchase() → TLStacks721._markIndicesMinted() → TLStacks721._updateDropState() → TLStacks721._settleUp() → TLStacks721._mintSelectedTokens() → IERC721TL.externalMint()` |
| State modified | `_mintedIndices[nft][round]`, `_drops[nft].supply`, `_numberMinted[nft][round][recipient][phase]` |
| Value flow | Same as `purchase` |
| Reentrancy guard | yes |

### `TLStacks1155.purchase()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, `nonReentrant`, `whenNotPaused` |
| Caller | Payer; may differ from `recipient`. The recipient receives the mint and consumes the phase allowance. |
| Parameters | `nftAddress`, `tokenId`, `recipient`, `numberToMint`, `presaleNumberCanMint`, `proof`, `currencyAddress`, `maxCostPerToken`, `expectedRound` (user-controlled) |
| Call chain | `→ TLStacks1155._updateDropState() → TLStacks1155._settleUp() → TransferHelper → TLStacks1155._mintToken() → IERC1155TL.externalMint()` |
| State modified | `_drops[nft][tokenId].supply`, `publicDuration` (velocity), `_numberMinted[nft][tokenId][round][recipient][phase]` |
| Value flow | Buyer → `drop.payoutReceiver` and `protocolFeeReceiver` |
| Reentrancy guard | yes |

### `RoyaltyLookup.getRoyalty()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Anyone (auction house calls it during settlement) |
| Parameters | `nftAddress`, `tokenId`, `value` (user-controlled) |
| Call chain | `→ IRoyaltyEngineV1.getRoyalty()` when `royaltyEngine` is set; otherwise `→ IERC2981.royaltyInfo()` |
| State modified | None |
| Value flow | None |
| Reentrancy guard | no |

---

## Role-Gated

| Contract | Function | Access | State modified | Value flow | Guard |
|----------|----------|--------|----------------|------------|-------|
| `TLAuctionHouse` | `list` | Token owner (`ownerOf`) | `_listings`, `_id` | NFT in | `nonReentrant`, `whenNotPaused` |
| `TLAuctionHouse` | `batchList` | Token owner, per item | `_listings`, `_id` | NFT in | `nonReentrant`, `whenNotPaused` |
| `TLAuctionHouse` | `updateListing` | `listing.seller`; no bid yet | `_listings` (new `id`) | None | `nonReentrant`, `whenNotPaused` |
| `TLAuctionHouse` | `updatePayoutReceiver` | `listing.seller` | `listing.payoutReceiver` | None | `whenNotPaused` |
| `TLAuctionHouse` | `delist` | `listing.seller`; no bid | deletes `_listings` | NFT out | `nonReentrant` |
| `TLAuctionHouse` | `topUpBid` | `listing.highestBidder` | `highestBid` | Currency in | `nonReentrant`, `whenNotPaused` |
| `TLAuctionHouse` | `cancelUnsettledAuction` | Seller or highest bidder; grace elapsed | deletes `_listings`; `claimableFunds`; `claimableNft` | Accounting only | `nonReentrant` |
| `TLAuctionHouse` | `claimNft` | `claimableNft[nft][token]` | deletes `claimableNft` | NFT out | `nonReentrant` |
| `TLAuctionHouse` | `acceptOwnership` | `pendingOwner` | `owner`, clears pending | None | inherited `Ownable2Step` |
| `TLStacks721` | `configureDrop` | Drop admin; mint role | `_drops`, maybe `_rounds` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropPayoutReceiver` | Drop admin; live drop | `payoutReceiver` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropAllowance` | Drop admin; live drop | `allowance` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropPrices` | Drop admin; live drop | currency and both costs | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropDuration` | Drop admin; live drop | `startTime`, durations | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropPresaleMerkleRoot` | Drop admin; live drop | `presaleMerkleRoot` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropDecayRate` | Drop admin; velocity only | `decayRate` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `updateDropSupply` | Drop admin; not selectable | `initialSupply`, `supply` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks721` | `closeDrop` | Drop admin | deletes `_drops`; `_rounds++` | None | `nonReentrant` |
| `TLStacks721` | `acceptOwnership` | `pendingOwner` | `owner` | None | inherited `Ownable2Step` |
| `TLStacks1155` | `configureDrop` | Drop admin; mint role | `_drops[nft][id]`, maybe `_rounds` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropPayoutReceiver` | Drop admin; live drop | `payoutReceiver` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropAllowance` | Drop admin; live drop | `allowance` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropPrices` | Drop admin; live drop | currency and both costs | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropDuration` | Drop admin; live drop | `startTime`, durations | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropPresaleMerkleRoot` | Drop admin; live drop | `presaleMerkleRoot` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropDecayRate` | Drop admin; velocity only | `decayRate` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `updateDropSupply` | Drop admin; live drop | `initialSupply`, `supply` | None | `nonReentrant`, `whenNotPaused` |
| `TLStacks1155` | `closeDrop` | Drop admin | deletes `_drops[nft][id]`; `_rounds++` | None | `nonReentrant` |
| `TLStacks1155` | `acceptOwnership` | `pendingOwner` | `owner` | None | inherited `Ownable2Step` |

Drop admin means `msg.sender` equals the NFT contract's `owner()` or holds `ADMIN_ROLE` (`keccak256("ADMIN_ROLE")`) on that contract. `configureDrop` also requires this contract to hold `APPROVED_MINT_CONTRACT`.

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| `TLAuctionHouse` | `setProtocolFeeSettings` | receiver, bps ≤ 500 | `protocolFeeReceiver`, `protocolFeeBps` |
| `TLAuctionHouse` | `setSanctionsOracle` | oracle | `SanctionsCompliance.oracle` |
| `TLAuctionHouse` | `setCurrencyAllowed` | currency, bool | `allowedCurrencies` |
| `TLAuctionHouse` | `setCreatorLookup` | helper | `creatorLookup` |
| `TLAuctionHouse` | `setRoyaltyLookup` | helper | `royaltyLookup` |
| `TLAuctionHouse` | `pause` | bool | Pausable flag |
| `TLAuctionHouse` | `removeProtocolFee` | nft, tokenId | `listing.zeroProtocolFee = true` |
| `TLAuctionHouse` | `transferOwnership` | new owner | `_pendingOwner` (inherited `Ownable2Step`) |
| `TLAuctionHouse` | `renounceOwnership` | — | `owner = address(0)` (inherited `Ownable`, not overridden) |
| `TLStacks721` | `setProtocolFeeSettings` | receiver, flat ETH fee, two bps ≤ 500 | `protocolFeeReceiver`, `protocolFee`, `ethSellerFeeBps`, `erc20SellerFeeBps` |
| `TLStacks721` | `waiveSellerFee` | nft | `_sellerFeeWaived[nft][round] = true` |
| `TLStacks721` | `setSanctionsOracle` | oracle | `oracle` |
| `TLStacks721` | `setCurrencyAllowed` | currency, bool | `allowedCurrencies` |
| `TLStacks721` | `withdrawFunds` | currency, amount | None (transfers balance) |
| `TLStacks721` | `pause` | bool | Pausable flag |
| `TLStacks721` | `transferOwnership` | new owner | `_pendingOwner` |
| `TLStacks721` | `renounceOwnership` | — | `owner = address(0)` |
| `TLStacks1155` | `setProtocolFeeSettings` | receiver, flat ETH fee, two bps ≤ 500 | same fee fields as 721 |
| `TLStacks1155` | `waiveSellerFee` | nft, tokenId | `_sellerFeeWaived[nft][tokenId][round] = true` |
| `TLStacks1155` | `setSanctionsOracle` | oracle | `oracle` |
| `TLStacks1155` | `setCurrencyAllowed` | currency, bool | `allowedCurrencies` |
| `TLStacks1155` | `withdrawFunds` | currency, amount | None (transfers balance) |
| `TLStacks1155` | `pause` | bool | Pausable flag |
| `TLStacks1155` | `transferOwnership` | new owner | `_pendingOwner` |
| `TLStacks1155` | `renounceOwnership` | — | `owner = address(0)` |
| `RoyaltyLookup` | `setRoyaltyEngine` | engine | `royaltyEngine` |
| `RoyaltyLookup` | `transferOwnership` | new owner | `owner` immediately (single-step `Ownable`) |
| `RoyaltyLookup` | `renounceOwnership` | — | `owner = address(0)` |

`CreatorLookup` has no state-changing entry point.

---

## Initialization

No `initialize`. Owners and the sanctions oracle are set in the constructors (`TLAuctionHouse.sol:92`, `TLStacks721.sol:68`, `TLStacks1155.sol:66`, `RoyaltyLookup.sol:30`). Stacks constructors also call `_setProtocolFeeSettings`.

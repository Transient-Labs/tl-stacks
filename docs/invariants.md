# Checks and properties

Companion to [Trust Model and Protections](trust-model.md). Transient Labs Stacks 2.8.0.

62 per-call checks, 15 properties inside one contract, 3 that cross contracts, 3 about how a sale is split. Seven of the properties are not enforced on-chain.

---

## 1. Enforced guards

Per-call checks. Each one is numbered so it can be cited.

#### G-1
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.updateListing` · `updateListing` is limited to the stored seller, which is also how a missing listing is rejected

#### G-2
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.updateListing` · terms stay fixed once a bid is stored on the listing

#### G-3
`if (config.type_ != listing.type_) revert InvalidListingType();` · `TLAuctionHouse.updateListing` · an update cannot switch the sale mechanism on a live listing

#### G-4
`if (config.currencyAddress != listing.currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.updateListing` · an update cannot switch the currency of a live listing

#### G-5
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.updatePayoutReceiver` · only the stored seller can change `payoutReceiver`

#### G-6
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.delist` · `delist` is limited to the stored seller

#### G-7
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.delist` · `delist` cannot pull an NFT that already has a stored bid

#### G-8
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.bid` · `bid` only proceeds when the stored type is an auction

#### G-9
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.bid` · a bid naming an old listing id cannot fill the listing now in storage

#### G-10
`if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.bid` · the bid currency must equal the currency stored on the listing

#### G-11
`if (block.timestamp < listing.openTime) revert CannotBidYet();` · `TLAuctionHouse.bid` · bids wait until the listing's stored open time

#### G-12
`if (amount == 0 || amount < listing.reservePrice) revert BidTooLow();` · `TLAuctionHouse.bid` · the first bid must clear the reserve stored on the listing

#### G-13
`if (block.timestamp > auctionEndTime) revert AuctionEnded();` · `TLAuctionHouse.bid` · a scheduled auction with no bids rejects a first bid after the stored end

#### G-14
`if (block.timestamp > auctionEndTime) revert AuctionEnded();` · `TLAuctionHouse.bid` · a later bid is rejected once the current stored end has passed

#### G-15
`if (amount < _calcNextBid(listing.highestBid)) revert BidTooLow();` · `TLAuctionHouse.bid` · an outbid must clear the 5% step off the stored high bid

#### G-16
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.topUpBid` · `topUpBid` only proceeds on a stored auction type

#### G-17
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.topUpBid` · a top-up naming an old listing id cannot raise the listing now in storage

#### G-18
`if (msg.sender != listing.highestBidder) revert NotHighestBidder();` · `TLAuctionHouse.topUpBid` · only the stored high bidder can add to the bid

#### G-19
`if (block.timestamp > auctionEndTime) revert AuctionEnded();` followed by `if (auctionEndTime - block.timestamp <= EXTENSION_TIME) revert TopUpWindowClosed();` · `TLAuctionHouse.topUpBid` · top-ups require strictly more than five minutes until the current stored end; the after-end check precedes subtraction, and this function does not write `duration`

#### G-20
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.settleAuction` · settlement only proceeds on a stored auction type

#### G-21
`if (listing.highestBidder == address(0)) revert AuctionNotStarted();` · `TLAuctionHouse.settleAuction` · settlement requires a stored high bidder

#### G-22
`if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();` · `TLAuctionHouse.settleAuction` · settlement waits until after the stored end time

#### G-23
`if (_isSanctioned(listing.seller)) revert SanctionedAddress();` · `TLAuctionHouse.settleAuction` · settlement re-reads sanctions for the stored seller

#### G-24
`if (_isSanctioned(listing.highestBidder)) revert SanctionedAddress();` · `TLAuctionHouse.settleAuction` · settlement re-reads sanctions for the stored high bidder

#### G-25
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.cancelUnsettledAuction` · unwind only proceeds on a stored auction type

#### G-26
`if (listing.highestBidder == address(0)) revert AuctionNotStarted();` · `TLAuctionHouse.cancelUnsettledAuction` · unwind requires a stored high bidder

#### G-27
`if (msg.sender != listing.seller && msg.sender != listing.highestBidder) revert NotSellerOrBidder();` · `TLAuctionHouse.cancelUnsettledAuction` · only the stored seller or stored high bidder can unwind

#### G-28
`if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD)` · `TLAuctionHouse.cancelUnsettledAuction` · unwind waits until the stored end plus the seven-day grace constant; the next line reverts `SettlementGracePeriodNotOver`

#### G-29
`if (!_hasBuyNow(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.buyNow` · `buyNow` only proceeds when the stored type has a fixed price

#### G-30
`if (listing.type_ == ListingType.PRIVATE_SALE && recipient != listing.recipient) revert InvalidRecipient();` · `TLAuctionHouse.buyNow` · a private sale delivers only to the recipient stored by the seller

#### G-31
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.buyNow` · a buy naming an old listing id cannot fill the listing now in storage

#### G-32
`if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.buyNow` · the buy currency must equal the currency stored on the listing

#### G-33
`if (listing.buyNowPrice > maxPrice) revert PriceTooHigh();` · `TLAuctionHouse.buyNow` · the buyer caps the price stored on the listing

#### G-34
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.buyNow` · buy-now stops once a bid is stored

#### G-35
`if (block.timestamp < listing.openTime) revert CannotBuyYet();` · `TLAuctionHouse.buyNow` · buys wait until the listing's stored open time

#### G-36
`if (amount == 0) revert NothingToClaim();` · `TLAuctionHouse._claimFunds` · `amount` was loaded from `claimableFunds[beneficiary][currencyAddress]` (via `claimFunds` or `retryPayout`); a zero stored credit cannot be withdrawn

#### G-37
`if (claimableNft[nftAddress][tokenId] != msg.sender) revert NothingToClaim();` · `TLAuctionHouse.claimNft` · the escrowed NFT is released only to the account stored for that token

#### G-38
`if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();` · `TLAuctionHouse.setProtocolFeeSettings` · the owner cannot store an auction protocol fee above 5%

#### G-39
`if (_listings[nftAddress][tokenId].type_ == ListingType.NOT_CONFIGURED) revert InvalidListingType();` · `TLAuctionHouse.removeProtocolFee` · the per-listing fee waiver applies only to a configured listing

#### G-40
`if (!_isCurrencyAllowed(config.currencyAddress)) revert CurrencyNotAllowed();` · `TLAuctionHouse._list`, `TLAuctionHouse.updateListing` · a new listing or `updateListing` term change requires ETH or a currency present in `allowedCurrencies`; existing execution and payout-only repair do not recheck admission

#### G-41
`if (_listings[config.nftAddress][config.tokenId].type_ != ListingType.NOT_CONFIGURED) revert AlreadyListed();` · `TLAuctionHouse._list` · a second `list` cannot overwrite a configured listing

#### G-42
`if (IERC721(config.nftAddress).ownerOf(config.tokenId) != msg.sender) revert NotTokenOwner();` · `TLAuctionHouse._list` · escrow starts only when `ownerOf` returns the caller

#### G-43
`if (listing.duration > MAX_AUCTION_DURATION) revert InvalidDuration();` · `TLAuctionHouse._buildListing` · a listing built by `_buildListing` cannot store a duration over 30 days

#### G-44
`if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` · `TLStacks721._setProtocolFeeSettings` · seller-fee rates stored for the 721 house stay at or below 5%

#### G-45
`if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` · `TLStacks1155._setProtocolFeeSettings` · seller-fee rates stored for the 1155 house stay at or below 5%

#### G-46
`if (drop.initialSupply != drop.supply) revert InvalidDropSupply();` · `TLStacks721.configureDrop` · a new 721 drop is stored with remaining supply equal to the total

#### G-47
`if (drop.initialSupply != drop.supply) revert InvalidDropSupply();` · `TLStacks1155.configureDrop` · a new 1155 drop is stored with remaining supply equal to the total

#### G-48
`if (mDrop.dropType != DropType.NOT_CONFIGURED && mPhase != DropPhase.ENDED)` · `TLStacks721.configureDrop` · a 721 drop that is still configured and not ended cannot be replaced; the next line reverts `DropAlreadyConfigured`

#### G-49
`if (mDrop.dropType != DropType.NOT_CONFIGURED && mPhase != DropPhase.ENDED)` · `TLStacks1155.configureDrop` · a 1155 drop that is still configured and not ended cannot be replaced; the next line reverts `DropAlreadyConfigured`

#### G-50
`if (_rounds[nftAddress] != expectedRound) revert DropRoundChanged();` · `TLStacks721._validatePurchase` · a 721 purchase naming an old round cannot mint the round now in storage

#### G-51
`if (_rounds[nftAddress][tokenId] != expectedRound) revert DropRoundChanged();` · `TLStacks1155.purchase` · a 1155 purchase naming an old round cannot mint the round now in storage

#### G-52
`if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();` · `TLStacks721._validatePurchase` · a 721 purchase cannot exceed the stored phase allowance or remaining `supply`

#### G-53
`if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();` · `TLStacks1155.purchase` · a 1155 purchase cannot exceed the stored phase allowance or remaining `supply`

#### G-54
`if (msg.value != totalSale + totalProtocolFee) revert IncorrectFunds();` · `TLStacks721._settleUp` · an ETH 721 purchase must match `numberToMint * cost` plus `numberToMint * protocolFee`

#### G-55
`if (msg.value != totalSale + totalProtocolFee) revert IncorrectFunds();` · `TLStacks1155._settleUp` · an ETH 1155 purchase must match `numberToMint * cost` plus `numberToMint * protocolFee`

#### G-56
`if (index >= initialSupply) revert IndexOutOfRange();` · `TLStacks721._markIndicesMinted` · a selectable index must sit below the drop's stored `initialSupply`

#### G-57
`if (mintedIndices.get(index)) revert IndexAlreadyMinted();` · `TLStacks721._markIndicesMinted` · a selectable index already set in this round's bitmap cannot be minted again

#### G-58
`if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();` · `TLStacks721.closeDrop` · `closeDrop` is limited to the NFT owner or `ADMIN_ROLE`; this function has no `whenNotPaused`

#### G-59
`if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();` · `TLStacks1155.closeDrop` · `closeDrop` is limited to the NFT owner or `ADMIN_ROLE`; this function has no `whenNotPaused`

#### G-60
`if (finalBalance - intialBalance < amount) revert InsufficentERC20Transfer();` · `TransferHelper._safeTransferFromERC20` · an inbound `transferFrom` must increase the recipient balance by the full `amount`

#### G-61
`if (newInitialSupply > drop.initialSupply || newInitialSupply < numberMinted) revert InvalidDropSupply();` · `TLStacks721.updateDropSupply` · a 721 supply cut stays between the number already minted and the stored total

#### G-62
`if (newInitialSupply > drop.initialSupply || newInitialSupply < numberMinted) revert InvalidDropSupply();` · `TLStacks1155.updateDropSupply` · a 1155 supply cut stays between the number already minted and the stored total

#### G-63
`if (!IERC1155TL(nftAddress).getTokenDetails(tokenId).created) revert TokenDoesntExist();` · `TLStacks1155.configureDrop` · ERC-1155 drop terms can only be configured for a token already created on the NFT contract; zero minted supply is allowed

#### G-64
`_validateDropDuration(startTime, presaleDuration, publicDuration)` · `TLStacks721` and `TLStacks1155` · configuration and duration updates require the complete endpoint to be at most `type(uint64).max`, using subtraction to avoid overflow while validating

#### G-65
`publicDuration + (numberToMint > remaining / rate ? remaining : rate * numberToMint)` · both `_updateDropState` helpers, for positive rates only · marathon extensions are capped at the remaining `uint64.max` endpoint allowance, compared before multiplication; at the ceiling, purchases still succeed and the schedule stops extending

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> While a `TLStacks721` drop is stored for the active round, `initialSupply == supply + Σ numberMinted[nft][round][*][PRESALE|PUBLIC_SALE]`.

**Derivation** — Δ-pair in `TLStacks721._updateDropState`: `Δ(supply) = -numberToMint` ↔ `Δ(_numberMinted) = +numberToMint`. `configureDrop` stores the drop only after `initialSupply == supply` and, when replacing an ended drop, increments `_rounds` so the new round's minted sum is 0. `updateDropSupply` sets `supply = newInitialSupply - (initialSupply - supply)` and writes both fields. `closeDrop` deletes the drop and increments the round. Selectable purchases call `_markIndicesMinted` and then the same Δ-pair with `indices.length`. No other function writes `supply` or `_numberMinted`.

**If violated** — Remaining supply and per-wallet counts would describe a different number of tokens than `initialSupply`.

---

#### I-2

`Conservation` · On-chain: **Yes**

> While a `TLStacks1155` drop is stored for the active round of `(nft, tokenId)`, `initialSupply == supply + Σ numberMinted[nft][tokenId][round][*][PRESALE|PUBLIC_SALE]`.

**Derivation** — Δ-pair in `TLStacks1155._updateDropState`: `Δ(supply) = -numberToMint` ↔ `Δ(_numberMinted) = +numberToMint`. `configureDrop` requires `initialSupply == supply` and increments `_rounds` when replacing an ended drop. `updateDropSupply` preserves `initialSupply - supply`. `closeDrop` deletes the drop and increments the round. No other function writes those fields.

**If violated** — Remaining supply and per-wallet counts for that token id would disagree with `initialSupply`.

---

#### I-3

`Bound` · On-chain: **Yes**

> `TLAuctionHouse.protocolFeeBps ∈ [0, MAX_PROTOCOL_FEE_BPS]` with `MAX_PROTOCOL_FEE_BPS = 500`.

**Derivation** — guard-lift: `if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();` in `TLAuctionHouse.setProtocolFeeSettings`. The only write is `protocolFeeBps = newProtocolFeeBps`, inside that function. The constructor does not assign it (storage default 0). `removeProtocolFee` writes `zeroProtocolFee`, not `protocolFeeBps`.

**If violated** — Settlement would compute `value * protocolFeeBps / BASIS` from a rate above 5%.

---

#### I-4

`Bound` · On-chain: **Yes**

> On both stacks contracts, `ethSellerFeeBps ∈ [0, 500]` and `erc20SellerFeeBps ∈ [0, 500]`.

**Derivation** — guard-lift: `if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` in `TLStacks721._setProtocolFeeSettings` and `TLStacks1155._setProtocolFeeSettings`. The only writes are the assignments in those same bodies. Both constructors call that function.

**If violated** — `_settleUp` would take more than 5% of `totalSale` as the seller fee.

---

#### I-5

`Bound` · On-chain: **No**

> `listing.duration <= MAX_AUCTION_DURATION` (30 days) for every stored listing.

**Derivation** — guard-lift: `if (listing.duration > MAX_AUCTION_DURATION) revert InvalidDuration();` at the end of `TLAuctionHouse._buildListing`, before the listing is stored. Write sites of `duration`: `_buildListing` assigns `config.auctionDuration` and then zeroes it for buy-now and private sale before the check; `bid` does `listing.duration += EXTENSION_TIME - timeRemaining` and stores the listing with no cap check. `topUpBid` does not write `duration`.

**If violated** — The stored auction end `startTime + duration` can sit past the 30-day configuration cap.

---

#### I-6

`StateMachine` · On-chain: **Yes**

> On a live listing, `zeroProtocolFee` moves from `false` to `true` and is not cleared in place.

**Derivation** — edge: `false` at the `_buildListing` field init in `list` → `true` in `TLAuctionHouse.removeProtocolFee`. `updateListing` passes the stored flag into `_buildListing`. No function assigns `false` on an existing listing. A new `list` starts a new id at `false`. NatSpec on `updateListing` — "a protocol fee removed by the contract owner stays removed".

**If violated** — A waived listing could start charging `protocolFeeBps` again without a new listing id.

---

#### I-7

`StateMachine` · On-chain: **Yes**

> For a given drop round, `_sellerFeeWaived` moves from `false` to `true` and is not cleared on that key.

**Derivation** — edge: default `false` → `true` in `TLStacks721.waiveSellerFee` and `TLStacks1155.waiveSellerFee`, which write only the round matching `expectedRound`. No function writes `false`. `closeDrop` and a reconfigure in `configureDrop` increment the round, so the next round is a new key.

**If violated** — A waived round could start charging the seller fee again without a new round.

---

#### I-8

`Temporal` · On-chain: **Yes**

> `settleAuction` runs only when `block.timestamp > listing.startTime + listing.duration`. `cancelUnsettledAuction` runs only when `block.timestamp > listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD`.

**Derivation** — temporal: `if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();` in `TLAuctionHouse.settleAuction`, and `if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD)` in `cancelUnsettledAuction`. Both read the stored end. `bid` checks the previous end before it extends `duration`.

**If violated** — Settlement or unwind would move escrow against a different clock than the one stored on the listing.

---

#### I-9

`Temporal` · On-chain: **No**

> `claimableFunds` and `claimableNft` are credited only by functions that carry `whenNotPaused`.

**Derivation** — `_credit` is reached from `_payout` during `bid`, `buyNow`, and `settleAuction` (all `whenNotPaused`). `cancelUnsettledAuction` has no `whenNotPaused`, calls `_credit` for the high bidder, and writes `claimableNft` for the seller. The NatSpec on `claimFunds`, `retryPayout`, and `claimNft` says only that they stay available while paused so existing credits remain recoverable; it does not claim credits arise only from pausable functions.

**If violated** — Credits can be recorded while `pause(true)` is set, through the unwind path.

---

#### I-10

`Temporal` · On-chain: **Yes**

> `topUpBid` does not change `listing.duration` or the auction end.

**Derivation** — `topUpBid` writes `highestBid` only and requires more than `EXTENSION_TIME` until the stored `startTime + duration`. It does not assign either time field. The extension write remains only in `bid`; regular bids by the incumbent also follow its minimum-increment and extension rules.

**If violated** — The current high bidder could move the end without a new bid.

---

#### I-11

`Conservation` · On-chain: **Yes**

> `claimFunds` and `retryPayout` send exactly the stored `claimableFunds[beneficiary][currency]` and set that entry to 0. Every increase of `claimableFunds` goes through `_credit`.

**Derivation** — Δ-pair in `TLAuctionHouse._claimFunds` (shared by `claimFunds`, where the beneficiary is `msg.sender`, and `retryPayout`, which pays the beneficiary itself): `Δ(claimableFunds[beneficiary][currency]) = -amount` with `amount` loaded just before, and the following transfer sends `amount`. The only increase is `claimableFunds[account][currency] += amount` in `_credit`. Callers of `_credit` are `_payout` (sanctioned payee and failed transfer) and `cancelUnsettledAuction`. No other assignment to `claimableFunds` exists.

**If violated** — A claim would pay a different amount than the credit that was recorded.

---

#### I-12

`Bound` · On-chain: **Yes**

> For a stored drop, `supply <= initialSupply`.

**Derivation** — guard-lift of `initialSupply == supply` in both `configureDrop` functions plus later writers. `_updateDropState` only decreases `supply` after `numberToMint <= numberCanMint <= supply` (`G-52`, `G-53`). `updateDropSupply` sets `supply = newInitialSupply - numberMinted` with `newInitialSupply >= numberMinted` (`G-61`, `G-62`), so `supply <= initialSupply` after the write. `closeDrop` deletes the struct.

**If violated** — Remaining supply would exceed the drop total the admin stored.

---

#### I-13

`Ratio` · On-chain: **Yes**

> In `_completeSale`, the protocol fee taken from `value` is `0` when `listing.zeroProtocolFee` is set, otherwise `value * protocolFeeBps / BASIS`.

**Derivation** — in `TLAuctionHouse._completeSale`, `protocolFee = Math.mulDiv(value, protocolFeeBps, BASIS)` (rounding down, without intermediate overflow) is computed after the listing is deleted, from the live `protocolFeeBps` storage, then subtracted from `remainingValue`. The snapshot is the rate at settlement, not the rate at `list` or `bid`.

**If violated** — The fee paid would not match the bps stored at settlement.

---

#### I-14

`Ratio` · On-chain: **Yes**

> Royalties paid by `_completeSale` are the amounts returned by `_capRoyalties`, whose running budget starts at `value * MAX_ROYALTY_BPS / BASIS` (`MAX_ROYALTY_BPS = 1000`) and never goes negative.

**Derivation** — `TLAuctionHouse._capRoyalties` sets `royaltyBudget = Math.mulDiv(value, MAX_ROYALTY_BPS, BASIS)`. Its loop assigns `cappedAmounts[i] = min(amounts[i], royaltyBudget)` and subtracts that from the budget, for at most `MAX_ROYALTY_RECIPIENTS` entries, skipping `address(0)` and `address(this)`. `_completeSale` pays those capped amounts. `_quoteRoyalties` is the only producer of the arrays that reach that loop during settlement. Primary sales skip the quote.

**If violated** — Royalty payouts could exceed 10% of `value` or pay more recipients than the cap.

---

#### I-15

`Bound` · On-chain: **No**

> `protocolFee` on `TLStacks721` and `TLStacks1155` is capped.

**Derivation** — guard-lift gap: `_setProtocolFeeSettings` assigns `protocolFee = newProtocolFee` in both `TLStacks721` and `TLStacks1155`. The requires in those functions bound the receiver and the seller-fee bps (`G-44`, `G-45`). Neither function constrains `newProtocolFee`. Those are the only writes. Constructors call the same function.

**If violated** — ETH purchases require `msg.value == totalSale + numberToMint * protocolFee` (`G-54`, `G-55`) for whatever `protocolFee` is stored.

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **No**

> The primary-versus-secondary classification of a listing is fixed when the listing is created.

**Caller side** — `TLAuctionHouse._isPrimarySale` calls `creatorLookup.getCreator` at settlement and treats `creator == seller` as primary; `_completeSale` then skips the royalty quote. Lookup failure returns secondary.

**Callee side** — `CreatorLookup.getCreator` returns `Ownable(nftAddress).owner()` and ignores `tokenId`. `TLAuctionHouse.setCreatorLookup` replaces `creatorLookup` with no read of existing listings. `CreatorLookup` itself stores no creator.

**If violated** — A sale that was primary under the helper at list time can be secondary at settlement, or the reverse, and royalties follow the later answer.

---

#### X-2

On-chain: **No**

> The royalty schedule used at settlement is the schedule implied by the listing at bid or buy time.

**Caller side** — `TLAuctionHouse._quoteRoyalties` calls `royaltyLookup.getRoyalty(nft, tokenId, value)` after the listing is deleted and before `_transferNft`.

**Callee side** — `RoyaltyLookup.getRoyalty` — when `royaltyEngine` has code and returns a payable schedule, the return value is the engine's arrays; otherwise it is the direct ERC-2981 result. `RoyaltyLookup.setRoyaltyEngine` and `TLAuctionHouse.setRoyaltyLookup` replace that source with no check against live listings.

**If violated** — Recipients and pre-cap amounts at settlement differ from the quote a bidder could have read earlier.

---

#### X-3

On-chain: **No**

> `RoyaltyLookup.getRoyalty` returns the NFT's ERC-2981 royalty.

**Caller side** — `TLAuctionHouse._quoteRoyalties` passes the arrays `getRoyalty` returned to `_capRoyalties`, which trusts them and then caps them (`I-14`).

**Callee side** — `RoyaltyLookup.getRoyalty` and `getRoyaltyView` prefer correctly shaped engine schedules with at least one nonzero amount to a nonzero recipient. Missing/codeless/reverting/mismatched engine schedules, and schedules with nothing payable, fall back to direct ERC-2981. A reverting `royaltyInfo` yields empty arrays; a malformed successful response reverts the helper, which the auction house catches as no royalty. The auction house does not call `royaltyInfo` itself, and a reverting helper results in no royalty. Selection precedes filters/caps, so nonzero engine royalties can still differ from direct royalties.

**If violated** — The auction house caps and pays a schedule that did not come from the token's `royaltyInfo`.

---

## 4. Economic Invariants

#### E-1

On-chain: **Yes**

> On a completed auction or buy-now, the protocol fee, the capped royalty amounts, and the `payoutReceiver` remainder add up to `value`. The protocol fee is 0 or `value * protocolFeeBps / BASIS` with `protocolFeeBps <= 500`. The royalty sum is at most `value * 1000 / 10000`. A secondary sale with the fee enabled therefore leaves the payout receiver at least 85% of `value`. A primary sale leaves at least 95%.

**Follows from** — `I-3` + `I-13` + `I-14`

**If violated** — The three payout legs would not partition the sale, or a leg would exceed its cap.

---

#### E-2

On-chain: **Yes**

> On a stacks purchase, the payout receiver gets `totalSale - sellerFee`, and `sellerFee` is 0 when the round is waived or else `totalSale * bps / BASIS` with `bps <= 500`. The receiver therefore gets at least 95% of the token price.

**Follows from** — `I-4` + `I-7`

**If violated** — The seller fee would take more than the capped bps, or a waived round would still take it.

---

#### E-3

On-chain: **No**

> The ETH a buyer must send for a stacks purchase is bounded by the token price alone.

**Follows from** — `I-15`

**If violated** — `msg.value` must also cover `numberToMint * protocolFee`, and `protocolFee` has no stored maximum. ERC-20 purchases do not add this flat fee (`_settleUp` in `TLStacks721` and `TLStacks1155`).

## Observation guard updates

The three sales contracts reject their own address at the externally selected recipient/payee boundaries. Auction escrow ingress still targets the auction house; royalty entries naming it remain skipped. Claims rejecting a self-address leave the credit/NFT claim intact for a valid retry. Mint contracts retain zero fee receivers when all fees are zero, but never accept their own address as fee receiver.

Ownership renunciation reverts in all three sales contracts, including while paused. Existing owner authentication, pending ownership, two-step acceptance, and cancellation of a pending handover remain intact.

## Automatic ETH payout gas configuration

`payoutGasLimit` initializes to `1e5` and can only be changed by the owner to a nonzero value. `_payout` reads it for each automatic ETH call, including outbid refunds and all sale payees. The setter emits previous/new values and remains usable while paused. No hard upper bound is enforced under the trusted owner model.

A failed call credits exactly its payment when the surrounding transaction can complete. The setting neither redirects credits nor changes their ownership. Transaction-wide exhaustion still rolls back the operation. Explicit claims use the available-gas atomic helper, and ERC-20 payouts use their existing separate path.

## Remaining audit fixes

- Protocol-owner fee waivers require the intended current round/listing ID. Empty-round mint waivers remain valid; an already-applied auction waiver survives a listing update, while a pending waiver against the old ID fails.
- A verified fresh NFT deposit retires any prior NFT claim within the atomic listing transaction. Transfer/postcondition/batch failures roll back retirement; bidder funds credits are independent.
- `retryPayout` can only pay a funded credit to its original beneficiary. The shared claim helper zeroes the balance before transfer; failure rolls back. Only the beneficiary's original `claimFunds` entry point permits redirection.
- Every listing-state function (`list`, `batchList`, `updateListing`, `updatePayoutReceiver`, `bid`, `topUpBid`) is `nonReentrant`, so callbacks cannot change a listing between its write and its event; live-listing events equal storage, and terminal events retain the historical deleted listing.
- `int256.min` rates cannot enter drop storage. Negative reductions saturate before multiplication, preserving zero/exact-boundary behavior; positive endpoint limits remain in force.
- Merkle verification bytes are unchanged; fixed vectors and [encoding guidance](presale-merkle.md) cover all mint routes.

# Checks and properties

Companion to [Trust Model and Protections](trust-model.md). Transient Labs Stacks 2.8.0.

62 per-call checks, 15 properties inside one contract, 3 that cross contracts, 3 about how a sale is split. Seven of the properties are not enforced on-chain.

---

## 1. Enforced guards

Per-call checks. Each one is numbered so it can be cited.

#### G-1
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.sol:145` · `updateListing` is limited to the stored seller, which is also how a missing listing is rejected

#### G-2
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.sol:149` · terms stay fixed once a bid is stored on the listing

#### G-3
`if (config.type_ != listing.type_) revert InvalidListingType();` · `TLAuctionHouse.sol:152` · an update cannot switch the sale mechanism on a live listing

#### G-4
`if (config.currencyAddress != listing.currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.sol:153` · an update cannot switch the currency of a live listing

#### G-5
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.sol:180` · only the stored seller can change `payoutReceiver`

#### G-6
`if (msg.sender != listing.seller) revert NotSeller();` · `TLAuctionHouse.sol:203` · `delist` is limited to the stored seller

#### G-7
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.sol:209` · `delist` cannot pull an NFT that already has a stored bid

#### G-8
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.sol:258` · `bid` only proceeds when the stored type is an auction

#### G-9
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.sol:261` · a bid naming an old listing id cannot fill the listing now in storage

#### G-10
`if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.sol:262` · the bid currency must equal the currency stored on the listing

#### G-11
`if (block.timestamp < listing.openTime) revert CannotBidYet();` · `TLAuctionHouse.sol:265` · bids wait until the listing's stored open time

#### G-12
`if (amount == 0 || amount < listing.reservePrice) revert BidTooLow();` · `TLAuctionHouse.sol:270` · the first bid must clear the reserve stored on the listing

#### G-13
`if (block.timestamp > auctionEndTime) revert AuctionEnded();` · `TLAuctionHouse.sol:283` · a scheduled auction with no bids rejects a first bid after the stored end

#### G-14
`if (block.timestamp > auctionEndTime) revert AuctionEnded();` · `TLAuctionHouse.sol:288` · a later bid is rejected once the current stored end has passed

#### G-15
`if (amount < _calcNextBid(listing.highestBid)) revert BidTooLow();` · `TLAuctionHouse.sol:291` · an outbid must clear the 5% step off the stored high bid

#### G-16
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.sol:344` · `topUpBid` only proceeds on a stored auction type

#### G-17
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.sol:347` · a top-up naming an old listing id cannot raise the listing now in storage

#### G-18
`if (msg.sender != listing.highestBidder) revert NotHighestBidder();` · `TLAuctionHouse.sol:350` · only the stored high bidder can add to the bid

#### G-19
`if (block.timestamp > listing.startTime + listing.duration) revert AuctionEnded();` · `TLAuctionHouse.sol:353` · top-ups stop at the stored end and this function does not write `duration`

#### G-20
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.sol:385` · settlement only proceeds on a stored auction type

#### G-21
`if (listing.highestBidder == address(0)) revert AuctionNotStarted();` · `TLAuctionHouse.sol:388` · settlement requires a stored high bidder

#### G-22
`if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();` · `TLAuctionHouse.sol:391` · settlement waits until after the stored end time

#### G-23
`if (_isSanctioned(listing.seller)) revert SanctionedAddress();` · `TLAuctionHouse.sol:394` · settlement re-reads sanctions for the stored seller

#### G-24
`if (_isSanctioned(listing.highestBidder)) revert SanctionedAddress();` · `TLAuctionHouse.sol:395` · settlement re-reads sanctions for the stored high bidder

#### G-25
`if (!_isAuction(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.sol:422` · unwind only proceeds on a stored auction type

#### G-26
`if (listing.highestBidder == address(0)) revert AuctionNotStarted();` · `TLAuctionHouse.sol:425` · unwind requires a stored high bidder

#### G-27
`if (msg.sender != listing.seller && msg.sender != listing.highestBidder) revert NotSellerOrBidder();` · `TLAuctionHouse.sol:428` · only the stored seller or stored high bidder can unwind

#### G-28
`if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD)` · `TLAuctionHouse.sol:431` · unwind waits until the stored end plus the seven-day grace constant; the next line reverts `SettlementGracePeriodNotOver`

#### G-29
`if (!_hasBuyNow(listing.type_)) revert InvalidListingType();` · `TLAuctionHouse.sol:481` · `buyNow` only proceeds when the stored type has a fixed price

#### G-30
`if (listing.type_ == ListingType.PRIVATE_SALE && recipient != listing.recipient) revert InvalidRecipient();` · `TLAuctionHouse.sol:484` · a private sale delivers only to the recipient stored by the seller

#### G-31
`if (listing.id != expectedListingId) revert ListingChanged();` · `TLAuctionHouse.sol:490` · a buy naming an old listing id cannot fill the listing now in storage

#### G-32
`if (listing.currencyAddress != currencyAddress) revert CurrencyMismatch();` · `TLAuctionHouse.sol:491` · the buy currency must equal the currency stored on the listing

#### G-33
`if (listing.buyNowPrice > maxPrice) revert PriceTooHigh();` · `TLAuctionHouse.sol:492` · the buyer caps the price stored on the listing

#### G-34
`if (listing.highestBidder != address(0)) revert AuctionStarted();` · `TLAuctionHouse.sol:495` · buy-now stops once a bid is stored

#### G-35
`if (block.timestamp < listing.openTime) revert CannotBuyYet();` · `TLAuctionHouse.sol:498` · buys wait until the listing's stored open time

#### G-36
`if (amount == 0) revert NothingToClaim();` · `TLAuctionHouse.sol:525` · `amount` was loaded from `claimableFunds[msg.sender][currencyAddress]`; a zero stored credit cannot be withdrawn

#### G-37
`if (claimableNft[nftAddress][tokenId] != msg.sender) revert NothingToClaim();` · `TLAuctionHouse.sol:551` · the escrowed NFT is released only to the account stored for that token

#### G-38
`if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();` · `TLAuctionHouse.sol:570` · the owner cannot store an auction protocol fee above 5%

#### G-39
`if (_listings[nftAddress][tokenId].type_ == ListingType.NOT_CONFIGURED) revert InvalidListingType();` · `TLAuctionHouse.sol:635` · the per-listing fee waiver applies only to a configured listing

#### G-40
`if (!_isCurrencyAllowed(config.currencyAddress)) revert CurrencyNotAllowed();` · `TLAuctionHouse.sol:722` · a new listing's currency must be ETH or present in `allowedCurrencies`

#### G-41
`if (_listings[config.nftAddress][config.tokenId].type_ != ListingType.NOT_CONFIGURED) revert AlreadyListed();` · `TLAuctionHouse.sol:725` · a second `list` cannot overwrite a configured listing

#### G-42
`if (IERC721(config.nftAddress).ownerOf(config.tokenId) != msg.sender) revert NotTokenOwner();` · `TLAuctionHouse.sol:728` · escrow starts only when `ownerOf` returns the caller

#### G-43
`if (listing.duration > MAX_AUCTION_DURATION) revert InvalidDuration();` · `TLAuctionHouse.sol:792` · a listing built by `_buildListing` cannot store a duration over 30 days

#### G-44
`if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` · `TLStacks721.sol:616` · seller-fee rates stored for the 721 house stay at or below 5%

#### G-45
`if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` · `TLStacks1155.sol:614` · seller-fee rates stored for the 1155 house stay at or below 5%

#### G-46
`if (drop.initialSupply != drop.supply) revert InvalidDropSupply();` · `TLStacks721.sol:175` · a new 721 drop is stored with remaining supply equal to the total

#### G-47
`if (drop.initialSupply != drop.supply) revert InvalidDropSupply();` · `TLStacks1155.sol:178` · a new 1155 drop is stored with remaining supply equal to the total

#### G-48
`if (mDrop.dropType != DropType.NOT_CONFIGURED && mPhase != DropPhase.ENDED)` · `TLStacks721.sol:183` · a 721 drop that is still configured and not ended cannot be replaced; the next line reverts `DropAlreadyConfigured`

#### G-49
`if (mDrop.dropType != DropType.NOT_CONFIGURED && mPhase != DropPhase.ENDED)` · `TLStacks1155.sol:188` · a 1155 drop that is still configured and not ended cannot be replaced; the next line reverts `DropAlreadyConfigured`

#### G-50
`if (_rounds[nftAddress] != expectedRound) revert DropRoundChanged();` · `TLStacks721.sol:718` · a 721 purchase naming an old round cannot mint the round now in storage

#### G-51
`if (_rounds[nftAddress][tokenId] != expectedRound) revert DropRoundChanged();` · `TLStacks1155.sol:476` · a 1155 purchase naming an old round cannot mint the round now in storage

#### G-52
`if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();` · `TLStacks721.sol:739` · a 721 purchase cannot exceed the stored phase allowance or remaining `supply`

#### G-53
`if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();` · `TLStacks1155.sol:499` · a 1155 purchase cannot exceed the stored phase allowance or remaining `supply`

#### G-54
`if (msg.value != totalSale + totalProtocolFee) revert IncorrectFunds();` · `TLStacks721.sol:818` · an ETH 721 purchase must match `numberToMint * cost` plus `numberToMint * protocolFee`

#### G-55
`if (msg.value != totalSale + totalProtocolFee) revert IncorrectFunds();` · `TLStacks1155.sol:751` · an ETH 1155 purchase must match `numberToMint * cost` plus `numberToMint * protocolFee`

#### G-56
`if (index >= initialSupply) revert IndexOutOfRange();` · `TLStacks721.sol:754` · a selectable index must sit below the drop's stored `initialSupply`

#### G-57
`if (mintedIndices.get(index)) revert IndexAlreadyMinted();` · `TLStacks721.sol:755` · a selectable index already set in this round's bitmap cannot be minted again

#### G-58
`if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();` · `TLStacks721.sol:387` · `closeDrop` is limited to the NFT owner or `ADMIN_ROLE`; this function has no `whenNotPaused`

#### G-59
`if (!_isDropAdmin(nftAddress)) revert NotDropAdmin();` · `TLStacks1155.sol:415` · `closeDrop` is limited to the NFT owner or `ADMIN_ROLE`; this function has no `whenNotPaused`

#### G-60
`if (finalBalance - intialBalance < amount) revert InsufficentERC20Transfer();` · `TransferHelper.sol:101` · an inbound `transferFrom` must increase the recipient balance by the full `amount`

#### G-61
`if (newInitialSupply > drop.initialSupply || newInitialSupply < numberMinted) revert InvalidDropSupply();` · `TLStacks721.sol:375` · a 721 supply cut stays between the number already minted and the stored total

#### G-62
`if (newInitialSupply > drop.initialSupply || newInitialSupply < numberMinted) revert InvalidDropSupply();` · `TLStacks1155.sol:403` · a 1155 supply cut stays between the number already minted and the stored total

---

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> While a `TLStacks721` drop is stored for the active round, `initialSupply == supply + Σ numberMinted[nft][round][*][PRESALE|PUBLIC_SALE]`.

**Derivation** — Δ-pair: `TLStacks721.sol:792` `Δ(supply) = -numberToMint` ↔ `TLStacks721.sol:793` `Δ(_numberMinted) = +numberToMint`. `configureDrop` stores the drop only after `initialSupply == supply` (`:175`) and, when replacing an ended drop, increments `_rounds` (`:191`) so the new round's minted sum is 0. `updateDropSupply` (`:373-380`) sets `supply = newInitialSupply - (initialSupply - supply)` and writes both fields. `closeDrop` deletes the drop and increments the round. Selectable purchases call `_markIndicesMinted` and then the same Δ-pair with `indices.length`. No other function writes `supply` or `_numberMinted`.

**If violated** — Remaining supply and per-wallet counts would describe a different number of tokens than `initialSupply`.

---

#### I-2

`Conservation` · On-chain: **Yes**

> While a `TLStacks1155` drop is stored for the active round of `(nft, tokenId)`, `initialSupply == supply + Σ numberMinted[nft][tokenId][round][*][PRESALE|PUBLIC_SALE]`.

**Derivation** — Δ-pair: `TLStacks1155.sol:719` `Δ(supply) = -numberToMint` ↔ `TLStacks1155.sol:720` `Δ(_numberMinted) = +numberToMint`. `configureDrop` requires `initialSupply == supply` (`:178`) and increments `_rounds` when replacing an ended drop (`:197`). `updateDropSupply` (`:402-409`) preserves `initialSupply - supply`. `closeDrop` deletes the drop and increments the round. No other function writes those fields.

**If violated** — Remaining supply and per-wallet counts for that token id would disagree with `initialSupply`.

---

#### I-3

`Bound` · On-chain: **Yes**

> `TLAuctionHouse.protocolFeeBps ∈ [0, MAX_PROTOCOL_FEE_BPS]` with `MAX_PROTOCOL_FEE_BPS = 500`.

**Derivation** — guard-lift: `if (newProtocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();` at `TLAuctionHouse.sol:570`. The only write is `protocolFeeBps = newProtocolFeeBps` at `:573`, inside that function. The constructor does not assign it (storage default 0). `removeProtocolFee` writes `zeroProtocolFee`, not `protocolFeeBps`.

**If violated** — Settlement would compute `value * protocolFeeBps / BASIS` from a rate above 5%.

---

#### I-4

`Bound` · On-chain: **Yes**

> On both stacks contracts, `ethSellerFeeBps ∈ [0, 500]` and `erc20SellerFeeBps ∈ [0, 500]`.

**Derivation** — guard-lift: `if (newEthSellerFeeBps > MAX_SELLER_FEE_BPS || newErc20SellerFeeBps > MAX_SELLER_FEE_BPS) revert InvalidSellerFeeBps();` at `TLStacks721.sol:616` and `TLStacks1155.sol:614`. The only writes are the assignments in those same `_setProtocolFeeSettings` bodies (`TLStacks721.sol:622-623`, `TLStacks1155.sol:620-621`). Constructors call that function (`TLStacks721.sol:76`, `TLStacks1155.sol:74`).

**If violated** — `_settleUp` would take more than 5% of `totalSale` as the seller fee.

---

#### I-5

`Bound` · On-chain: **No**

> `listing.duration <= MAX_AUCTION_DURATION` (30 days) for every stored listing.

**Derivation** — guard-lift: `if (listing.duration > MAX_AUCTION_DURATION) revert InvalidDuration();` at `TLAuctionHouse.sol:792`, applied inside `_buildListing` before the listing is stored. Write sites of `duration`: `_buildListing` assigns `config.auctionDuration` (`:763`) and then zeroes it for buy-now and private sale (`:780`, `:784`) before the check; `bid` does `listing.duration += EXTENSION_TIME - timeRemaining` at `:300` and stores the listing at `:304` with no cap check. `topUpBid` does not write `duration`.

**If violated** — The stored auction end `startTime + duration` can sit past the 30-day configuration cap.

---

#### I-6

`StateMachine` · On-chain: **Yes**

> On a live listing, `zeroProtocolFee` moves from `false` to `true` and is not cleared in place.

**Derivation** — edge: `false` at `_buildListing` field init `TLAuctionHouse.sol:756` → `true` at `removeProtocolFee` `:637`. `updateListing` passes the stored flag into `_buildListing` (`:156`). No function assigns `false` on an existing listing. A new `list` starts a new id at `false`. NatSpec: `TLAuctionHouse.sol:137` — "a protocol fee removed by the contract owner stays removed".

**If violated** — A waived listing could start charging `protocolFeeBps` again without a new listing id.

---

#### I-7

`StateMachine` · On-chain: **Yes**

> For a given drop round, `_sellerFeeWaived` moves from `false` to `true` and is not cleared on that key.

**Derivation** — edge: default `false` → `true` at `TLStacks721.waiveSellerFee` `:105` and `TLStacks1155.waiveSellerFee` `:104`. No function writes `false`. `closeDrop` and a reconfigure increment the round (`TLStacks721.sol:393`, `TLStacks1155.sol:421`, configure paths `:191` and `:197`), so the next round is a new key.

**If violated** — A waived round could start charging the seller fee again without a new round.

---

#### I-8

`Temporal` · On-chain: **Yes**

> `settleAuction` runs only when `block.timestamp > listing.startTime + listing.duration`. `cancelUnsettledAuction` runs only when `block.timestamp > listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD`.

**Derivation** — temporal: `if (block.timestamp <= listing.startTime + listing.duration) revert AuctionNotEnded();` at `TLAuctionHouse.sol:391`, and `if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD)` at `:431`. Both read the stored end. `bid` checks the previous end (`:283`, `:288`) before it extends `duration` (`:300`).

**If violated** — Settlement or unwind would move escrow against a different clock than the one stored on the listing.

---

#### I-9

`Temporal` · On-chain: **No**

> `claimableFunds` and `claimableNft` are credited only by functions that carry `whenNotPaused`.

**Derivation** — NatSpec: `TLAuctionHouse.sol:517` — "Not gated by pause, since funds can only be credited through pausable functions". The matching NFT comment is at `:544` — "nfts can only be credited through pausable functions". `_credit` (`:844`) is reached from `_payout` during `bid`, `buyNow`, and `settleAuction` (all `whenNotPaused`). `cancelUnsettledAuction` (`:417`) has no `whenNotPaused` and calls `_credit` at `:439` and writes `claimableNft` at `:440`.

**If violated** — Credits can be recorded while `pause(true)` is set, through the unwind path.

---

#### I-10

`Temporal` · On-chain: **Yes**

> `topUpBid` does not change `listing.duration` or the auction end.

**Derivation** — NatSpec: `TLAuctionHouse.sol:326` — "topping up never extends the auction, so the highest bidder can't hold an auction open indefinitely". The body (`:331-366`) writes `highestBid` only (`:359-360`). The end check at `:353` uses the stored `startTime + duration` and does not assign either field. The extension write is only in `bid` at `:300`.

**If violated** — The current high bidder could move the end without a new bid.

---

#### I-11

`Conservation` · On-chain: **Yes**

> `claimFunds` sends exactly the stored `claimableFunds[msg.sender][currency]` and sets that entry to 0. Every increase of `claimableFunds` goes through `_credit`.

**Derivation** — Δ-pair: `TLAuctionHouse.sol:528` `Δ(claimableFunds[msg.sender][currency]) = -amount` with `amount` loaded at `:524`, and the following transfer sends `amount` (`:530-534`). The only increase is `claimableFunds[account][currency] += amount` at `:844`. Callers of `_credit` are `_payout` (`:855`, `:865`) and `cancelUnsettledAuction` (`:439`). No other assignment to `claimableFunds` exists.

**If violated** — A claim would pay a different amount than the credit that was recorded.

---

#### I-12

`Bound` · On-chain: **Yes**

> For a stored drop, `supply <= initialSupply`.

**Derivation** — guard-lift of `initialSupply == supply` at configure (`TLStacks721.sol:175`, `TLStacks1155.sol:178`) plus later writers. `_updateDropState` only decreases `supply` (`TLStacks721.sol:792`, `TLStacks1155.sol:719`) after `numberToMint <= numberCanMint <= supply` (`G-52`, `G-53`). `updateDropSupply` sets `supply = newInitialSupply - numberMinted` with `newInitialSupply >= numberMinted` (`G-61`, `G-62`), so `supply <= initialSupply` after the write. `closeDrop` deletes the struct.

**If violated** — Remaining supply would exceed the drop total the admin stored.

---

#### I-13

`Ratio` · On-chain: **Yes**

> In `_completeSale`, the protocol fee taken from `value` is `0` when `listing.zeroProtocolFee` is set, otherwise `value * protocolFeeBps / BASIS`.

**Derivation** — `TLAuctionHouse.sol:928-930`: `protocolFee = value * protocolFeeBps / BASIS` is computed after the listing is deleted, from the live `protocolFeeBps` storage, then subtracted from `remainingValue`. The snapshot is the rate at settlement, not the rate at `list` or `bid`.

**If violated** — The fee paid would not match the bps stored at settlement.

---

#### I-14

`Ratio` · On-chain: **Yes**

> Royalties paid by `_completeSale` are the amounts returned by `_capRoyalties`, whose running budget starts at `value * MAX_ROYALTY_BPS / BASIS` (`MAX_ROYALTY_BPS = 1000`) and never goes negative.

**Derivation** — `TLAuctionHouse.sol:882` sets `royaltyBudget = value * MAX_ROYALTY_BPS / BASIS`. The loop at `:883-888` assigns `cappedAmounts[i] = min(amounts[i], royaltyBudget)` and subtracts that from the budget, for at most `MAX_ROYALTY_RECIPIENTS` entries, skipping `address(0)` and `address(this)`. `_completeSale:936-938` pays those capped amounts. `_quoteRoyalties:901` is the only producer of the arrays that reach that loop. Primary sales skip the quote (`:919`).

**If violated** — Royalty payouts could exceed 10% of `value` or pay more recipients than the cap.

---

#### I-15

`Bound` · On-chain: **No**

> `protocolFee` on `TLStacks721` and `TLStacks1155` is capped.

**Derivation** — guard-lift gap: `_setProtocolFeeSettings` assigns `protocolFee = newProtocolFee` at `TLStacks721.sol:621` and `TLStacks1155.sol:619`. The requires in those functions bound the receiver (`:611-615` and `:609-613`) and the seller-fee bps (`G-44`, `G-45`). Neither function constrains `newProtocolFee`. Those are the only writes. Constructors call the same function.

**If violated** — ETH purchases require `msg.value == totalSale + numberToMint * protocolFee` (`G-54`, `G-55`) for whatever `protocolFee` is stored.

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **No**

> The primary-versus-secondary classification of a listing is fixed when the listing is created.

**Caller side** — `TLAuctionHouse.sol:832-838` — `_isPrimarySale` calls `creatorLookup.getCreator` at settlement and treats `creator == seller` as primary, skipping royalties (`:919`). Lookup failure returns secondary.

**Callee side** — `CreatorLookup.sol:39` — `getCreator` returns `Ownable(nftAddress).owner()` and ignores `tokenId`. `TLAuctionHouse.setCreatorLookup:604` replaces `creatorLookup` with no read of existing listings. `CreatorLookup` itself stores no creator.

**If violated** — A sale that was primary under the helper at list time can be secondary at settlement, or the reverse, and royalties follow the later answer.

---

#### X-2

On-chain: **No**

> The royalty schedule used at settlement is the schedule implied by the listing at bid or buy time.

**Caller side** — `TLAuctionHouse.sol:897-901` — `_quoteRoyalties` calls `royaltyLookup.getRoyalty(nft, tokenId, value)` after the listing is deleted and before `_transferNft`.

**Callee side** — `RoyaltyLookup.sol:42-60` — when `royaltyEngine` is non-zero, the return value is the engine's arrays (or empty on failure). `setRoyaltyEngine:99` and `TLAuctionHouse.setRoyaltyLookup:614` replace that source with no check against live listings.

**If violated** — Recipients and pre-cap amounts at settlement differ from the quote a bidder could have read earlier.

---

#### X-3

On-chain: **No**

> `RoyaltyLookup.getRoyalty` returns the NFT's ERC-2981 royalty.

**Caller side** — `TLAuctionHouse.sol:901` — `_capRoyalties` trusts the arrays `getRoyalty` returned, then caps them (`I-14`).

**Callee side** — `RoyaltyLookup.sol:42-54` — if `royaltyEngine != address(0)` the function returns `royaltyEngine.getRoyalty` and does not call `royaltyInfo`. ERC-2981 is only the `else` branch at `:60`. `setRoyaltyEngine:99` is the write that selects the branch.

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

**If violated** — `msg.value` must also cover `numberToMint * protocolFee`, and `protocolFee` has no stored maximum. ERC-20 purchases do not add this flat fee (`TLStacks721.sol:821-824`, `TLStacks1155.sol:754-757`).

# Trust Model and Protections

Transient Labs Stacks, version 2.8.0 (`v2.8.0` at `484d7ca`). Solidity 0.8.30.

This document describes who is trusted, what the contracts enforce, and where a protection stops. Line references point at the source. Statements taken from `README.md` rather than from a check in the code are marked as operational practice.

[entry-points.md](entry-points.md) lists every state-changing function and who can call it. [invariants.md](invariants.md) is the check-by-check list, including the properties the code does not enforce.

The system has two jobs:

- `TLAuctionHouse` escrows an ERC-721 and the current high bid, then settles the sale.
- `TLStacks721` and `TLStacks1155` mint into an external creator contract and forward payment in the same transaction. They do not hold sale proceeds.

There is no protocol token. ETH is always an allowed currency. Any other currency must be on an owner-managed allowlist.

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 463 196" width="100%" font-family="Arial, sans-serif" role="img" aria-label="Transient Labs Stacks architecture">
  <defs>
    <marker id="tl-arch-arrow" viewBox="0 0 8 6" refX="8" refY="3"
      markerWidth="4" markerHeight="3" orient="auto">
      <path d="M0.5,0.5 L7,3 L0.5,5.5" fill="none" stroke="#94A3B8"
        stroke-width="1.2" stroke-linejoin="round" stroke-linecap="round"/>
    </marker>
    <filter id="tl-arch-shadow" x="-6%" y="-8%" width="112%" height="128%">
      <feDropShadow dx="0" dy="0.5" stdDeviation="0.8"
        flood-color="#000" flood-opacity="0.05"/>
    </filter>
  </defs>
  <rect width="463" height="196" fill="#F8F9FB" rx="3"/>
  <text x="231" y="11" text-anchor="middle" font-size="6" font-weight="700" fill="#1E293B">Transient Labs Stacks Architecture</text>
  <rect x="156" y="16" width="150" height="10" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.4"/>
  <rect x="161" y="18.5" width="5" height="5" rx="2.5" fill="#fff" stroke="#E2E5EA" stroke-width="0.4"/>
  <text x="169" y="22.5" font-size="3.5" fill="#1E293B">Actor</text>
  <rect x="201" y="18.5" width="5" height="5" rx="1.5" fill="#fff" stroke="#E2E5EA" stroke-width="0.4"/>
  <rect x="202" y="19.5" width="0.8" height="3" rx="0.4" fill="#3B82F6"/>
  <text x="209" y="22.5" font-size="3.5" fill="#1E293B">Protocol</text>
  <rect x="249" y="18.5" width="5" height="5" rx="1.5" fill="#fff" stroke="#E2E5EA" stroke-width="0.4"/>
  <rect x="250" y="19.5" width="0.8" height="3" rx="0.4" fill="#F59E0B"/>
  <text x="257" y="22.5" font-size="3.5" fill="#1E293B">External</text>
  <rect x="20.0" y="84.0" width="422.8" height="40.0" rx="5" fill="#EDEEF2"/>
  <text x="439.8" y="89.0" text-anchor="end" font-size="3.5" fill="#94A3B8" font-weight="500">Protocol</text>
  <rect x="20.0" y="146.0" width="422.8" height="40.0" rx="5" fill="#EDEEF2"/>
  <text x="439.8" y="151.0" text-anchor="end" font-size="3.5" fill="#94A3B8" font-weight="500">External</text>
  <path d="M104.4,46.0 C104.4,70.0 178.0,70.0 178.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M195.0,46.0 C195.0,70.0 178.0,70.0 178.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M195.0,46.0 C195.0,70.0 286.0,70.0 286.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M390.6,46.0 C390.6,70.0 286.0,70.0 286.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M291.0,46.0 C291.0,70.0 178.0,70.0 178.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M291.0,46.0 C291.0,70.0 286.0,70.0 286.0,94.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M134.4,112.0 C127.8,126.0 119.0,126.0 112.4,114.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M221.6,112.0 C260.2,130.0 311.8,130.0 350.4,114.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M178.0,114.0 C178.0,135.0 108.0,135.0 108.0,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M178.0,114.0 C178.0,135.0 227.4,135.0 227.4,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M286.0,114.0 C286.0,135.0 108.0,135.0 108.0,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M286.0,114.0 C286.0,135.0 227.4,135.0 227.4,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M391.6,114.0 C391.6,135.0 345.6,135.0 345.6,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <path d="M71.2,114.0 C71.2,135.0 108.0,135.0 108.0,156.0" fill="none" stroke="#94A3B8" stroke-width="0.5" marker-end="url(#tl-arch-arrow)"/>
  <g filter="url(#tl-arch-shadow)">
    <rect x="74.6" y="32.0" width="59.6" height="14" rx="7" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <text x="104.4" y="40.8" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">Seller</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="156.2" y="32.0" width="77.6" height="14" rx="7" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <text x="195.0" y="40.8" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">Buyer</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="348.2" y="32.0" width="84.8" height="14" rx="7" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <text x="390.6" y="40.8" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">DropAdmin</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="255.8" y="32.0" width="70.4" height="14" rx="7" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <text x="291.0" y="40.8" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">Owner</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="30.0" y="94.0" width="82.4" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="33.0" y="97.0" width="1.4" height="14" rx="0.6" fill="#3B82F6"/>
    <text x="71.2" y="103.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">CreatorLookup</text>
    <text x="71.2" y="108.5" text-anchor="middle" font-size="3.5" fill="#64748B">Collection owner</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="134.4" y="94.0" width="87.2" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="137.4" y="97.0" width="1.4" height="14" rx="0.6" fill="#3B82F6"/>
    <text x="178.0" y="103.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">TLAuctionHouse</text>
    <text x="178.0" y="108.5" text-anchor="middle" font-size="3.5" fill="#64748B">Escrow sales</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="350.4" y="94.0" width="82.4" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="353.4" y="97.0" width="1.4" height="14" rx="0.6" fill="#3B82F6"/>
    <text x="391.6" y="103.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">RoyaltyLookup</text>
    <text x="391.6" y="108.5" text-anchor="middle" font-size="3.5" fill="#64748B">Engine or 2981</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="243.6" y="94.0" width="84.8" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="246.6" y="97.0" width="1.4" height="14" rx="0.6" fill="#3B82F6"/>
    <text x="286.0" y="103.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">TLStacks</text>
    <text x="286.0" y="108.5" text-anchor="middle" font-size="3.5" fill="#64748B">721 and 1155 mints</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="65.6" y="156.0" width="84.8" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="68.6" y="159.0" width="1.4" height="14" rx="0.6" fill="#F59E0B"/>
    <text x="108.0" y="165.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">NFT</text>
    <text x="108.0" y="170.5" text-anchor="middle" font-size="3.5" fill="#64748B">ERC-721 / ERC-1155</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="172.4" y="156.0" width="110.0" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="175.4" y="159.0" width="1.4" height="14" rx="0.6" fill="#F59E0B"/>
    <text x="227.4" y="165.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">Currency</text>
    <text x="227.4" y="170.5" text-anchor="middle" font-size="3.5" fill="#64748B">ETH or allowlisted ERC-20</text>
  </g>
  <g filter="url(#tl-arch-shadow)">
    <rect x="304.4" y="156.0" width="82.4" height="20" rx="3" fill="#fff" stroke="#E2E5EA" stroke-width="0.5"/>
    <rect x="307.4" y="159.0" width="1.4" height="14" rx="0.6" fill="#F59E0B"/>
    <text x="345.6" y="165.5" text-anchor="middle" font-size="4.8" font-weight="600" fill="#1E293B">RoyaltyEngine</text>
    <text x="345.6" y="170.5" text-anchor="middle" font-size="3.5" fill="#64748B">External registry</text>
  </g>
  <rect x="121.2" y="65.0" width="40.0" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="141.2" y="70.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">list and delist</text>
  <rect x="171.3" y="65.0" width="30.4" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="186.5" y="70.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">bid and buy</text>
  <rect x="222.9" y="65.0" width="35.2" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="240.5" y="70.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">purchase drop</text>
  <rect x="319.5" y="65.0" width="37.6" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="338.3" y="70.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">configure drop</text>
  <rect x="215.7" y="57.0" width="37.6" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="234.5" y="62.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">fees and pause</text>
  <rect x="266.1" y="65.0" width="44.8" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="288.5" y="70.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">fees and withdraw</text>
  <rect x="107.0" y="125.0" width="32.8" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="123.4" y="130.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">read creator</text>
  <rect x="268.4" y="129.0" width="35.2" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="286.0" y="134.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">quote royalty</text>
  <rect x="126.6" y="134.0" width="32.8" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="143.0" y="139.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">escrow token</text>
  <rect x="186.3" y="130.0" width="32.8" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="202.7" y="135.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">escrow funds</text>
  <rect x="180.6" y="122.0" width="32.8" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="197.0" y="127.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">mint edition</text>
  <rect x="234.7" y="128.0" width="28.0" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="248.7" y="133.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">pay seller</text>
  <rect x="349.8" y="130.0" width="37.6" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="368.6" y="135.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">registry quote</text>
  <rect x="75.6" y="130.0" width="28.0" height="6.0" rx="1" fill="#F8F9FB"/>
  <text x="89.6" y="135.0" font-size="4" fill="#1E293B" font-weight="500" text-anchor="middle">read owner</text>
</svg>

---

## 1. Roles

Five roles show up in these contracts. Each one is a different address, and a deployment chooses whether any of them are the same key.

| Role | Where it lives | How it changes hands | What it can change immediately |
|------|----------------|----------------------|--------------------------------|
| Protocol owner | `TLAuctionHouse`, `TLStacks721`, `TLStacks1155` | `Ownable2Step`: `transferOwnership` names a pending owner, `acceptOwnership` completes it. `renounceOwnership` is inherited from `Ownable` and is not overridden, so the current owner can set the owner to the zero address in one call. | Fees, sanctions oracle, currency allowlist, pause. On the auction house: creator lookup, royalty lookup, and a per-listing fee waiver. On the stacks contracts: `withdrawFunds`. |
| Royalty-lookup owner | `RoyaltyLookup` | Single-step `Ownable.transferOwnership`. The new owner is set in the same transaction. | `setRoyaltyEngine`. |
| Drop admin | The NFT contract, outside this repo | Whatever that contract uses for `owner()` and `ADMIN_ROLE` | Live drop terms: price, currency, window, merkle root, decay rate, supply, payout receiver. `closeDrop`. |
| Seller | Stored as `listing.seller` when the token owner lists | Fixed for the life of that listing | Terms before the first bid. Payout receiver until settlement. `delist` only while there is no bid. |
| Buyer, bidder, settler | No stored role | Anyone | Pay, bid, mint, or call `settleAuction`. |

`CreatorLookup` has no owner and no writable state. It returns the NFT contract's current `owner()` and ignores the token id (`CreatorLookup.sol:39`).

Operational practice, from the README: contracts are deployed with CREATE2, constructor arguments start as defaults, an EOA configures them, then ownership is transferred to a multisig. The two-step transfer is what the multisig must accept. Nothing in the source delays the configuration calls that happen before that acceptance, or the operational calls that happen after it.

There is no timelock on any operational function.

---

## 2. What the protocol owner is trusted with

The protocol owner is trusted. Two-step transfer protects **who becomes owner**. It does not delay what the current owner can do.

On the auction house the owner can, in one transaction:

- Set `protocolFeeBps` up to 500 (5%). The cap is checked at the only write (`TLAuctionHouse.sol:570`). Settlement reads the **current** rate, not the rate at listing time (`TLAuctionHouse.sol:929`).
- Point `creatorLookup` and `royaltyLookup` at new contracts (`setCreatorLookup`, `setRoyaltyLookup`). Existing listings are not snapshotted.
- Point the sanctions oracle at a new contract, or at `address(0)` to disable checks.
- Add or remove an ERC-20 from the allowlist. Removal blocks new listings only. Listings already stored keep their currency (`setCurrencyAllowed` comment).
- Pause and unpause.
- Set `zeroProtocolFee` on one listing. That flag stays set if the seller later calls `updateListing` (`TLAuctionHouse.sol:156`, `:637`).

On each stacks contract the owner can:

- Set the flat ETH `protocolFee` with **no upper bound** (`TLStacks721.sol:621`, `TLStacks1155.sol:619`). Seller-fee rates are capped at 5% (`:616` and `:614`).
- Waive the seller fee for the current drop round. The waiver is not cleared on that round. A new round starts unwaved.
- Allowlist currencies, swap the sanctions oracle, and pause.
- Call `withdrawFunds` for any currency, including ETH. The function is not pause-gated. The contracts are written not to escrow user funds. The owner can still pull any balance that is sitting on the contract.

`RoyaltyLookup`'s owner can swap the royalty engine in one transaction, and can hand that contract over in one transaction. That owner is stored on its own. A deployment that wants one multisig for both has to set both owners to it.

---

## 3. What a drop admin is trusted with

Drop configuration belongs to the NFT contract. `configureDrop` and every `updateDrop*` function require the caller to be that contract's `owner()` or to hold `ADMIN_ROLE` on it. `configureDrop` also requires this stacks contract to hold `APPROVED_MINT_CONTRACT` on the NFT.

A drop admin can rewrite a live drop: payout receiver, public allowance, both prices and the currency, the time window, the presale merkle root, the velocity decay rate, and (except on selectable 721 drops) the total supply downward. `closeDrop` deletes the drop and increments the round. `closeDrop` does not use `whenNotPaused` and does not check sanctions (`TLStacks721.sol:386`, `TLStacks1155.sol:414`).

Buyers are pinned to three fields of their own choosing: `expectedRound`, `currencyAddress`, and `maxCostPerToken`. A change of round, currency, or token price above that max makes the pending purchase revert. A change of phase, merkle root, allowance, or duration can still change whether the purchase succeeds and which phase price it pays, as long as the price stays within `maxCostPerToken` and the currency is unchanged.

---

## 4. Protections for buyers and bidders

### Auction

`bid` and `buyNow` require the caller to name the listing id and the currency stored on the listing. `buyNow` also requires `listing.buyNowPrice <= maxPrice`. A seller who delists and relists, or who calls `updateListing` (which mints a new listing id), cannot be filled by a transaction signed against the old terms (`TLAuctionHouse.sol:261`, `:347`, `:490`).

The first bid must be non-zero and at least the reserve. A later bid from someone else must be at least 5% above the stored high bid, rounded up (`_calcNextBid`, `TLAuctionHouse.sol:291`). `topUpBid` is different on purpose: only the current high bidder can call it, any non-zero amount is accepted, and the auction end does not move (`TLAuctionHouse.sol:326`, `:353`, `:359`).

The NFT is transferred to the buyer before any of the price is paid out (`_completeSale`, transfer at `:923`, payouts after). If a payout reverts or the recipient is sanctioned, the amount is credited to `claimableFunds` and the sale still completes. The buyer does not depend on the seller's receiver accepting ETH.

While a bid is escrowed, the seller cannot `delist` and cannot change the listing type or currency. They can still change `payoutReceiver`. That address is the seller's payee. It does not change the price the bidder pays.

`settleAuction` can be called by anyone once `block.timestamp` is past `startTime + duration`. The buyer does not depend on the seller to finish the sale.

### Mints

`purchase` and `purchaseSelected` use the same three pins: round, currency, and max cost per token. Presale mints also require a merkle proof of `(recipient, presaleNumberCanMint)`. The payer and the recipient may differ. Both are checked against the sanctions oracle.

The recipient, rather than the payer, owns and consumes the phase allowance. This lets any payer complete a presale mint or gift without a recipient signature, but it also means a caller who can satisfy the purchase requirements can consume that recipient's remaining allowance by minting to them. The recipient receives the tokens and the caller pays the full price and fees. This denial-of-service surface is an accepted limitation of permissionless delegation.

For selectable drops, `indices` are public calldata and each index can be minted once per round. An eligible buyer who observes a pending selection may mint the desired index first, causing the original transaction to revert, and may later resell that token. This ordering risk is more material than for regular mints because regular mint outputs are semi-fungible. Appropriate pricing and private transaction submission can reduce the incentive and exposure, but do not provide an on-chain guarantee. Preserving one-transaction delegated minting makes this an accepted limitation.

ETH purchases must send exactly `numberToMint * cost + numberToMint * protocolFee`. A fee change between signature and inclusion makes the transaction revert with `IncorrectFunds` rather than pulling a different amount. ERC-20 purchases must send no ETH. The flat protocol fee is charged on ETH drops only.

Payment is forwarded before `externalMint`. If the mint reverts, the whole transaction reverts, including the transfers.

Selectable 721 drops mark each chosen index in a per-round bitmap before minting. An index at or above `initialSupply`, or an index already set in that round, reverts (`TLStacks721.sol:754`).

### Shared

- Inbound ERC-20 pulls measure the recipient balance and revert if the received amount is short (`TransferHelper.sol:101`). Fee-on-transfer tokens fail on the way in.
- `nonReentrant` is on every function that escrows, bids, buys, settles, claims, or mints.
- `whenNotPaused` is on `list`, `batchList`, `updateListing`, `updatePayoutReceiver`, `bid`, `topUpBid`, `settleAuction`, `buyNow`, drop configuration updates, and both purchase functions.

---

## 5. Protections for sellers

Only the stored seller can update a listing, change the payout receiver, or delist. `delist` additionally requires that nobody has bid, and it is **not** pause-gated, so a seller can take an unbid NFT back while the house is paused (`TLAuctionHouse.sol:197`).

After a bid exists, the seller's exit is settlement or, once seven days have passed after the end, `cancelUnsettledAuction`. Cancel credits the high bid to the bidder's `claimableFunds` and holds the NFT for the seller in `claimableNft`. The cancel itself makes no external call, so a broken token or a reverting payee cannot block it. Either the seller or the high bidder may call it. The README states that this remains available even when settlement would still succeed.

If the owner removes the protocol fee on a listing, `updateListing` keeps that waiver.

On drops, the payout receiver is chosen by the drop admin and can be changed while the drop is live. The seller fee taken from the token price is at most 5%, or zero for a waived round. The flat ETH protocol fee is paid by the buyer on top of the price, not out of the seller's proceeds.

`claimFunds` pays the caller's stored credit to an address they choose, and sets the credit to zero in the same call. A failed transfer reverts, so the credit is not cleared. `claimNft` releases the escrowed token only to the account stored in `claimableNft`.

---

## 6. Economic bounds the code actually stores

These hold because every write site checks them, or because the only payout path computes them.

| Bound | Where | Holds for |
|-------|--------|-----------|
| Auction protocol fee ≤ 5% of the sale | `protocolFeeBps` write at `TLAuctionHouse.sol:570`, applied at `:929` | Every settlement, unless `zeroProtocolFee` is set, in which case the fee is 0 |
| Royalties paid ≤ 10% of the sale, at most 10 recipients | `_capRoyalties` at `TLAuctionHouse.sol:882` | Every settlement that pays royalties. Primary sales skip the quote. |
| Seller fee on mints ≤ 5% of the token price | `ethSellerFeeBps` and `erc20SellerFeeBps` writes | Both stacks contracts. A waived round pays 0. |
| Auction fee + royalty cap < 100% | Constants 500 + 1000 < 10_000 | The subtraction in `_completeSale` (`:935`) |
| `supply <= initialSupply` on a stored drop | Configure requires equality; purchases only decrease `supply`; supply cuts cannot go below the number minted | Both stacks contracts |
| Active-round conservation | `initialSupply == supply + Σ minted` for the current round | Both stacks contracts, while the drop is stored |

Consequences, when those bounds hold:

- A secondary auction with the protocol fee left on pays the seller's receiver at least 85% of the price. A primary auction pays at least 95%, because royalties are skipped.
- A mint pays the drop's payout receiver at least 95% of the token price.

The flat ETH `protocolFee` on mints is not in that table. A buyer of an ETH drop must also send `numberToMint * protocolFee`, and nothing in the setter caps that fee. The buyer's `maxCostPerToken` does not cover it. The exact-`msg.value` check means a surprise increase reverts the purchase. It does not silently pull more.

`listing.duration <= 30 days` is checked when a listing is built (`TLAuctionHouse.sol:792`). It is not checked when `bid` extends the duration (`:300`). A bid inside the last five minutes sets the end to five minutes from now. Repeated bids in that window keep moving the end. `topUpBid` cannot do this. `MAX_AUCTION_DURATION` is a cap on the duration stored at configuration, not a cap on how long an auction can run once bidding has started.

---

## 7. Pause

`pause(true)` is owner-only and immediate. It stops new listings, listing edits, bids, top-ups, buy-now, settlement, drop edits, and purchases.

It does not stop:

| Function | What it still does while paused |
|----------|---------------------------------|
| `delist` | Returns an NFT that has no bid |
| `cancelUnsettledAuction` | Credits the bid and holds the NFT for the seller |
| `claimFunds`, `claimNft` | Pull stored credits |
| `closeDrop` | Deletes a drop and bumps the round |
| `withdrawFunds` | Sends the stacks contract's balance to the owner |
| Owner setters | Fees, oracle, allowlist, lookups, waivers |

`claimFunds` and `claimNft` say, in NatSpec, that credits only happen inside pausable functions (`TLAuctionHouse.sol:517`, `:544`). `cancelUnsettledAuction` is the exception: it credits both `claimableFunds` and `claimableNft` and it is not pause-gated (`:417`, `:439`, `:440`). That unwind is available during a pause on purpose. The NatSpec reason is narrower than the code.

---

## 8. Escrow accounting

The auction house does not keep a single "total escrow" number. The books are per listing and per account:

- The live bid for a token is `listing.highestBid`, in `listing.currencyAddress`.
- A replaced bid is sent back to the previous bidder, or added to `claimableFunds` if the send fails or the bidder is sanctioned.
- `claimFunds` pays exactly the stored credit and zeroes it. Every increase goes through `_credit` (`TLAuctionHouse.sol:528`, `:844`).
- After grace-period cancel, the bid amount moves from the listing into `claimableFunds`, and the NFT is recorded in `claimableNft` for the seller.

Settlement deletes the listing before payouts. A failure after that point still credits rather than reverting, so the NFT is not stuck in the house because a royalty recipient rejected a payment. The credited party pulls later.

Stacks purchases do not leave a balance by design. Seller proceeds and the protocol fee are transferred before the mint. `withdrawFunds` exists for balances that arrive some other way.

---

## 9. External systems

Each dependency has a failure mode. The auction house and the stacks contracts do not all fail the same way.

| Dependency | What the contracts assume | If it fails or lies |
|------------|---------------------------|---------------------|
| Sanctions oracle (`SanctionsCompliance.sol:55`) | `isSanctioned` is a current boolean. `address(0)` disables checks. | A revert halts the call. There is no try/catch. The owner can point this at any address. |
| Royalty engine, via `RoyaltyLookup` | The returned arrays are the royalty for `value`. | Empty arrays if the engine is an EOA, the call reverts, or the lengths differ. Settlement then pays the seller the royalty share. The auction house still caps whatever arrays do come back. |
| ERC-2981 on the NFT | Used only when no engine is set. | Same empty-array fallback. |
| `CreatorLookup` | The collection's current owner is the creator of every token. | Lookup failure is treated as a **secondary** sale, so royalties are quoted. A match with the seller is a **primary** sale, and royalties are skipped. |
| Creator `externalMint` | The mint delivers the tokens or reverts. The implementation is `tl-creator-contracts` 4.1.1, outside this repo. | A revert rolls the purchase back, including payment. |
| ERC-721 `transferFrom` / `ownerOf` | The token moves, and `ownerOf` afterwards equals the recipient. | `NftTransferFailed` if `ownerOf` disagrees. A token that callbacks during `transferFrom` hits `nonReentrant` on the escrow functions. `updatePayoutReceiver` does not use that guard. |
| Allowlisted ERC-20 | Balances of this contract change only through its own transfers. Outbound transfers deliver the full amount. | Inbound shortfalls revert. Outbound transfers (`_safeTransferERC20`, `_trySafeTransferERC20`) do not measure the balance delta. A fee on the way out, or a rebase, can leave `claimableFunds` or a stored bid larger than the balance. The README says those tokens must not be allowlisted. The code does not detect them. |

Royalty amounts are quoted **before** the NFT leaves escrow (`_quoteRoyalties` at `:893`, transfer at `:923`). A royalty rule that reads `ownerOf` sees the auction house, not the seller or the buyer. That order is intentional (`105e494`).

Primary versus secondary is also decided at settlement, from the helper installed at that moment. Changing `creatorLookup`, changing the engine, or changing the NFT contract's owner between list and settle changes who is treated as creator and who is paid royalties. Caps still apply to the amounts.

---

## 10. Sanctions

A sanctioned caller cannot list, bid, buy, mint, or claim. Recipients and payout receivers are checked when they are set.

Settlement checks the seller and the high bidder again (`TLAuctionHouse.sol:394`). A bid can be placed after the seller becomes sanctioned. Settlement then reverts until the oracle no longer flags either party. The README describes the intended path: the bid stays escrowed until the auction ends and the seven-day grace period passes, then the seller or the high bidder cancels, and a sanctioned claimant cannot pull `claimableFunds` or `claimableNft` until the flag clears. There is no function that refunds a bid at the moment the oracle flips.

`closeDrop` does not consult the oracle.

---

## 11. How the two sales differ

| | Auction house | Stacks mints |
|--|----------------|--------------|
| Custody | Holds the NFT and the high bid until settlement or cancel | Forwards payment, then mints. No user escrow. |
| Who configures a sale | The token owner | The NFT's owner or `ADMIN_ROLE` |
| Protocol fee | Up to 5% of the price, taken from the seller's side, read at settlement | Flat ETH per token on ETH drops, paid by the buyer, uncapped. Plus a seller fee of up to 5% taken from the price. |
| Buyer pin | Listing id, currency, and for buy-now a max price | Round, currency, max cost per token |
| Expiry | Auctions end at `startTime + duration`, extended by late bids. Buy-now and private sale have no end time. | The drop phase is derived from `startTime` and the two durations. Velocity mints add or subtract `decayRate * numberToMint` from `publicDuration`. |
| Failed payout | Credit and continue | The transfer uses the reverting helpers, so the purchase reverts |

---

## 12. What to verify before a deployment is treated as live

The source leaves these as operational conditions. They are the checks that make the trust model above the one the contracts describe.

1. The three sales-contract owners and the `RoyaltyLookup` owner are the intended multisigs, and each pending `transferOwnership` has been accepted.
2. `protocolFeeBps`, both seller-fee rates, and the flat `protocolFee` are the intended numbers. The flat fee has no on-chain maximum.
3. `creatorLookup` is the deployed `CreatorLookup`, and `royaltyLookup` points at a `RoyaltyLookup` whose engine is the intended registry or `address(0)` for ERC-2981 only.
4. The sanctions oracle is the intended Chainalysis oracle, or `address(0)` if checks are meant to be off.
5. Every allowlisted ERC-20 is a standard token: no transfer fee, no rebase, no balance that moves by itself. Decimals should be high enough that a 5% bid step is meaningful.
6. Each creator contract has granted `APPROVED_MINT_CONTRACT` to the stacks contract that should mint for it, and its `ADMIN_ROLE` holders are the people who should be able to rewrite a live drop.
7. Users who need an exit during a pause know that `delist` (no bid), `cancelUnsettledAuction` (after the grace period), `claimFunds`, and `claimNft` stay open, and that `settleAuction` does not.

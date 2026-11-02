# Transient Labs Stacks v2.8.0 — response to Hexwarden audit v1

Prepared November 1, 2026 for auditor remediation review.

Source: [Hexwarden audit v1, dated October 20, 2026](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf). This response covers all **35 findings and 27 observations**, retaining the report's severity labels and page references. Entry titles summarize the reported issues.

The audited/base revision is `3a52148d850b354b6307c819cb01e8e2805e937a`. Remediations described here are present in the local working tree on that base; they have not yet been assigned a remediation commit in this response. The auditor should review this document alongside the matching source patch or committed revision. No deployment or auditor acceptance is asserted.

## Disposition summary

All items have a team disposition, and all selected implementation work is complete locally. **Implemented** means a code change was made and locally validated. **Documentation updated** identifies documentation changes, with tests where stated. **Acknowledged** means the reported behavior or residual risk is accepted under the stated product policy, integration constraint, or trust assumption; it does not mean the behavior is impossible.

The main accepted boundaries are current collection-admin authority, seller transaction ordering, mutable NFT transfer policies, token issuer powers, required sanctions-oracle availability when configured, and responsibility for caller-selected recipient contracts. These boundaries are documented in the [README](../README.md), [trust model](../docs/trust-model.md), [entry points](../docs/entry-points.md), and [invariants](../docs/invariants.md).

## Findings

### HEX-001 — Royalty failures become zero royalties

**Medium · Implemented.** [Report p. 8](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=8)

Royalty-engine failures, or engine schedules with nothing payable, now trigger a direct ERC-2981 lookup inside `RoyaltyLookup`. Both view and settlement paths use this policy. A correctly shaped engine schedule that pays a nonzero amount to a nonzero recipient takes precedence; the auction house's filtering and existing caps apply after one schedule is selected. The auction-house royalty code is unchanged from the audited revision apart from HEX-018: it calls the helper inside `try/catch` and never decodes an NFT's `royaltyInfo` itself, so a malformed NFT response reverts only the helper call and the sale completes without a royalty. A reverting helper likewise results in no royalty, and an unset (codeless) auction-house `royaltyLookup` still disables royalties. Direct lookup failure remains best effort, so royalties are not guaranteed for every NFT or dependency failure. See HEX-016 and the royalty implementation references below.

### HEX-002 — Seller-fee waiver reaches a successor mint round

**Medium · Implemented.** [Report p. 11](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=11)

Both minters now require `expectedRound` in `waiveSellerFee` and revert with `DropRoundChanged` on mismatch. This prevents a pending waiver from affecting a successor round. Waivers for the current empty round remain supported and survive its initial configuration; successor rounds reset the waiver. Unchecked overloads were removed and repository callers migrated.

### HEX-003 — Protocol-fee removal reaches a successor listing

**Medium · Implemented.** [Report p. 13](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=13)

`removeProtocolFee` now requires `expectedListingId` and rejects mismatches with `ListingChanged`. A waiver already applied to a listing survives an authorized listing update, while a pending waiver signed against the prior ID cannot apply to the updated or replacement listing. Repository callers were migrated.

### HEX-004 — Stale listing updates overwrite replacement terms

**Medium · Acknowledged.** [Report p. 15](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=15)

A seller who remains authorized can execute a pending update against a replacement listing. Sellers are responsible for sequencing and canceling their instructions, including smart-account or queued operations. No expected-listing-ID requirement was added to seller updates. The behavior and coordination responsibility are documented.

### HEX-005 — Stale payout updates redirect successor-listing proceeds

**Medium · Acknowledged.** [Report p. 17](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=17)

Payout updates remain controlled by the currently authorized seller, who is responsible for transaction ordering and validating the payout address. No listing-ID binding was added to this operation. Sellers may update the receiver during an auction; a later failed payout credits the configured receiver, not automatically the seller.

### HEX-006 — Stale prices underprice a successor mint round

**Medium · Acknowledged.** [Report p. 19](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=19)

All currently authorized collection owners/admins are trusted to manage the active drop, including its prices. The collection owner must coordinate pending operations among admins. No round binding was added to these setters; this trust boundary is documented for both minters.

### HEX-007 — Stale close/configure calls replace successor drops

**Medium · Acknowledged.** [Report p. 21](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=21)

Closing and configuring drops remain powers of currently authorized collection owners/admins. Coordination of pending calls and replacement rounds is the collection team's responsibility. No additional lifecycle version or round-binding requirement was added to these operations.

### HEX-008 — Stale payout changes redirect successor-drop proceeds

**Medium · Acknowledged.** [Report p. 24](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=24)

Currently authorized collection owners/admins may change the active drop's payout receiver. Teams must coordinate admin operations and validate recipient addresses. No round binding was added; the shared collection-admin trust model is documented.

### HEX-009 — Old NFT recovery rights can withdraw later escrow

**Medium · Implemented.** [Report p. 27](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=27)

New listing admission retires any prior NFT claim after checking that no live listing exists and that the caller currently owns the token. `NftClaimRetired` records the old claimant and new seller. Escrow transfer verifies resulting ownership; a transfer or batch failure rolls back claim retirement. This isolates new escrow from stale recovery rights without requiring a separate deposit transaction. NFT-reported ownership remains trusted, and privileged transfers out and back between protocol calls cannot be detected universally.

### HEX-010 — Credits can be inaccessible to non-calling contracts

**Medium · Implemented.** [Report p. 30](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=30)

Anyone can call `retryPayout(beneficiary, currencyAddress)` to retry an existing credit to its original beneficiary. Only the beneficiary can redirect funds through `claimFunds`. A failed retry preserves the credit atomically; both paths remain available while paused and retain sanctions checks. No administrator can redirect claims. A permanently incompatible receiver, or a successful transfer to an unintended address, is not rescued. Failed seller proceeds belong to the configured payout receiver.

### HEX-011 — Fees and royalties can change after a binding bid

**Medium · Acknowledged.** [Report p. 33](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=33)

Settlement uses current fees and royalties within the existing limits, rather than snapshotting them when the bid is placed. This is an intentional economic policy. Mutable settlement terms and the royalty caps are documented; no fee or royalty snapshot was added.

### HEX-012 — Turning royalties on activates an incompatible transfer validator

**Medium · Acknowledged.** [Report p. 36](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=36)

Changing royalty settings may activate an incompatible NFT transfer policy after escrow begins. The NFT contract controls that policy. Marketplaces should check transfer policies before permitting listings, but those checks cannot guarantee future delivery. Failed settlement reverts; delayed cancellation can credit the bidder without an NFT transfer, while the seller's later NFT claim may still fail.

### HEX-013 — Replacing a transfer validator defeats auction finality

**Medium · Acknowledged.** [Report p. 38](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=38)

A collection can replace its transfer validator after listing, preventing settlement. This is an external collection trust boundary. Pre-listing compatibility checks are recommended for integrating marketplaces; they cannot freeze later policy changes. Existing delayed cancellation provides bidder accounting recovery, not guaranteed NFT delivery.

### HEX-014 — Inbound transfers work while every outbound transfer fails

**Medium · Acknowledged.** [Report p. 41](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=41)

Successful inbound escrow does not prove outbound transfer compatibility. The protocol retains atomic settlement and delayed cancellation rather than claiming universal validator support. The seller's NFT claim can remain blocked by the collection's policy; this limitation is documented.

### HEX-015 — A sender-frozen currency leaves sellers with inaccessible credits

**Medium · Acknowledged.** [Report p. 43](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=43)

An allowlisted ERC-20 issuer can freeze the auction house and prevent payments or withdrawals. Currencies must be chosen carefully, including their issuer powers and transfer behavior. Recording a credit preserves accounting but cannot guarantee liquidity while the token blocks transfers. No issuer-freeze bypass was added.

### HEX-016 — Royalty-engine negative-cache poisoning

**Medium · Implemented.** [Report p. 46](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=46)

Empty, all-zero, or otherwise unpayable royalty-engine results no longer prevent a direct ERC-2981 fallback, addressing the reported negative-cache case. Missing, codeless, reverting, and mismatched-array engine results also fall back. The fallback lives in `RoyaltyLookup`; the auction house consumes the helper's result as before. One schedule is selected before filtering/capping; primary-sale royalty omission and best-effort direct-call failure handling remain intentional. See HEX-001.

### HEX-017 — Pending presale purchases consume public allowance

**Low · Acknowledged.** [Report p. 48](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=48)

Mint purchases use the phase and corresponding allowance at execution time. No expected-phase parameter was added. Documentation now describes the actual transaction checks and no longer implies blanket protection against phase changes or all forms of front-running.

### HEX-018 — Intermediate percentage overflow blocks large-unit auctions

**Low · Implemented.** [Report p. 50](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=50)

Auction protocol-fee and royalty-cap calculations use OpenZeppelin `Math.mulDiv`, avoiding intermediate percentage overflow while preserving floor rounding. Large-value ERC-20 regressions cover payouts, capped royalty quotes, settlement, balance conservation, and NFT delivery. Final amounts and transaction totals must still fit their types.

### HEX-019 — Stale cancellations terminate successor listings

**Low · Acknowledged.** [Report p. 53](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=53)

Pending seller cancellation/delisting instructions may affect a successor listing if the caller remains authorized. Ordering and canceling these instructions is the seller's responsibility. No additional seller-operation identity guard was added; the limitation is documented with HEX-004/005.

### HEX-020 — Last-window top-ups suppress competing bids

**Low · Implemented.** [Report p. 55](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=55)

`topUpBid` rejects calls when five minutes or less remain in the auction, using `TopUpWindowClosed`. Arbitrary positive top-ups remain available earlier. Normal bids, including self-bids, still require the existing minimum increment and can trigger anti-snipe extension. Integrations should make the top-up cutoff visible in the UI.

### HEX-021 — Future ERC-1155 IDs inherit predecessor sale configuration

**Low · Implemented.** [Report p. 57](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=57)

ERC-1155 drop configuration now requires `IERC1155TL.getTokenDetails(tokenId).created`; uncreated IDs revert with `TokenDoesntExist`. An already-created token with zero supply remains valid. This prevents configuring sale terms for future IDs and makes the required collection interface explicit.

### HEX-022 — Duration updates leave overflowing phase endpoints

**Low · Implemented.** [Report p. 60](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=60)

Both minters validate the complete phase endpoint, including start time, presale duration, and public duration, against `uint64.max`. Configuration and duration updates reject invalid values before state changes; positive marathon extensions are capped at that ceiling rather than overflowing (see OBS-023). Public inputs remain `uint256`; exact-boundary and overflowing-input regressions cover both minters. See OBS-003/023.

### HEX-023 — Ownership changes make a secondary auction primary

**Low · Acknowledged.** [Report p. 63](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=63)

Primary-sale classification uses current collection ownership at settlement. An ownership change after bidding can therefore change royalty treatment. No ownership snapshot was added; collection ownership and its economic consequences remain part of the documented trust model.

### HEX-024 — Unbounded optional lookups consume settlement gas

**Low · Acknowledged.** [Report p. 65](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=65)

Creator and royalty dependency calls retain their existing uncapped gas behavior. No hard gas limits were added to these lookups. A failing or gas-consuming dependency can prevent settlement; delayed cancellation remains available under its existing conditions. Best-effort lookup handling is not a universal gas-exhaustion guarantee.

### HEX-025 — Oracle errors prevent fallback payment credits

**Low · Acknowledged.** [Report p. 67](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=67)

A configured sanctions oracle is a required dependency; its errors revert instead of being bypassed through fallback credits. Setting the oracle to `address(0)` disables screening, and the protocol owner can replace it. No fail-open payment or credit path was added.

### HEX-026 — An undeliverable winner forces delayed cancellation

**Low · Acknowledged.** [Report p. 69](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=69)

A validator can make delivery to a winning bidder impossible. Settlement reverts, and cancellation becomes available after the auction end plus the existing seven-day delay. Cancellation credits the bidder without requiring an external transfer; the NFT claim remains subject to collection policy. Marketplaces should screen policy compatibility before listing.

### HEX-027 — TRACE authority can remove an auction's NFT

**Low · Acknowledged.** [Report p. 72](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=72)

TRACE is a physical certificate-of-authenticity product rather than an intended auction asset. Its privileged NFT movement is outside the intended auction integration model. No TRACE-specific admission ban was added. The independent stale-claim/new-escrow isolation issue is fixed under HEX-009.

### HEX-028 — Malformed direct lookup responses evade the intended catch

**Low · Acknowledged.** [Report p. 74](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=74)

Protocol-selected royalty adapters are trusted to return valid ABI data. Malformed successful responses from those adapters can still revert during auction-house decoding; no additional defensive decoder was added. The direct ERC-2981 fallback added for HEX-001/016 runs inside `RoyaltyLookup`, not the auction house, so a malformed NFT response reverts the helper call, which the auction house catches as no royalty; it cannot block settlement. These changes do not claim to handle gas exhaustion (see HEX-024).

### HEX-029 — Mint fees can reach a newly sanctioned fee receiver

**Low · Acknowledged.** [Report p. 77](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=77)

The protocol owner is responsible for monitoring and replacing a fee receiver whose sanctions status changes. Configuration-time screening remains; no per-purchase recheck was added for the mint fee receiver. This responsibility and the absence of continuous screening are documented.

### HEX-030 — Selectable sales do not work with Editions metadata

**Low · Acknowledged.** [Report p. 79](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=79)

Selectable minting is incompatible with Editions behavior that ignores the selected token URI. Integrations must use compatible collections and expose this constraint. No on-chain Editions restriction was added; the limitation is documented.

### HEX-031 — Stale access/timing updates affect successor allocations

**Low · Acknowledged.** [Report p. 82](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=82)

Currently authorized collection owners/admins may change access and timing settings for the active round. Teams must coordinate pending transactions across admins and rounds. No expected-round requirement was added to these setters.

### HEX-032 — Stale decay/supply updates prematurely end successor drops

**Low · Acknowledged.** [Report p. 85](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=85)

Decay and supply updates remain within the authority of current collection owners/admins. Stale instructions must be managed by the collection team. No round binding was added; the separate arithmetic safeguards are implemented under HEX-022 and OBS-021/022/023.

### HEX-033 — Old listing creation can recreate a canceled sale

**Low · Acknowledged.** [Report p. 88](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=88)

A queued listing-creation instruction can recreate a canceled sale if its caller still meets ownership and approval requirements. Sellers are responsible for sequencing or canceling queued instructions. No persistent lifecycle nonce was introduced for creation.

### HEX-034 — Intermediate seller-fee overflow rejects mint purchases

**Low · Implemented.** [Report p. 90](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=90)

Both minters calculate seller fees with `Math.mulDiv`, preserving floor rounding without intermediate multiplication overflow. Tests cover large raw ERC-20 values through actual purchase routes, including selectable minting. This shares the arithmetic policy and validation approach of HEX-018.

### HEX-035 — Regular self-bids extend beyond the initial maximum duration

**Low · Acknowledged.** [Report p. 92](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=92)

The 30-day maximum limits the initial auction duration. Valid anti-snipe bids can extend the auction beyond that duration, including bids by the current highest bidder that satisfy the minimum increment. Documentation and NatSpec now state this distinction; no cumulative extension cap was added.

## Observations

### OBS-001 — Generic mint compatibility is overstated

**Documentation updated.** [Report p. 94](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=94)

Compatibility claims now describe the required collection interfaces instead of implying arbitrary NFT support. In particular, ERC-1155 configuration requires `getTokenDetails(...).created` under HEX-021. Transfer-policy and selectable-mint compatibility limits are also documented.

### OBS-002 — ERC-721 mints can land in incapable contracts

**Implemented with accepted limitation.** [Report p. 97](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=97)

Mint NFT recipients cannot be the minter itself. Other contract recipients remain caller-selected and must be capable of managing the asset. No universal contract-capability or receiver-hook requirement was added; the residual limitation is documented.

### OBS-003 — Static schedules can overflow phase calculation

**Implemented.** [Report p. 100](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=100)

Complete static schedule endpoints are validated against `uint64.max` at configuration and duration updates. This is covered by HEX-022, including exact-limit and overflowing combinations of start, presale, and public durations.

### OBS-004 — Pause does not stop auction time

**Acknowledged.** [Report p. 102](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=102)

Pause does not freeze wall-clock time or extend auction deadlines. Auctions can expire while paused. This behavior is documented; no pause-duration accounting was added.

### OBS-005 — Renouncing ownership removes oracle repair

**Implemented.** [Report p. 104](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=104)

Ownership renunciation is disabled in the auction house and both minters with `OwnershipRenunciationDisabled`. Two-step ownership transfer remains available so oracle repair authority can be retained and transferred. Collection governance and the separate royalty helper were not given this restriction.

### OBS-006 — Accidental direct ERC-20 transfers are unrecoverable

**Acknowledged.** [Report p. 106](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=106)

Accidental direct ERC-20 transfers do not create a claim or sale allocation and are not promised recovery. No new admin sweep, surplus accounting, or recovery mechanism was added. Documentation instructs users to use supported entry points.

### OBS-007 — Tokens requiring receiver hooks on raw transfers cannot list

**Acknowledged.** [Report p. 108](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=108)

NFTs that require a receiver hook even for raw `transferFrom` are unsupported by auction escrow. No `onERC721Received` hook was added for hypothetical compatibility. Failed listing admission reverts atomically; documentation narrows the compatibility claim.

### OBS-008 — Native mint payout receivers can consume the gas budget

**Acknowledged.** [Report p. 110](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=110)

Native mint payouts remain atomic and use the all-available-gas transfer helper. A receiver can revert or consume gas, causing the purchase to revert; funds and mint state roll back, while the buyer still pays transaction gas. No mint payout gas cap or deferred mint-credit system was added. The auction-specific gas setting below does not apply to minters.

### OBS-009 — Bidding contracts may be unable to use their NFT award

**Acknowledged.** [Report p. 112](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=112)

A contract bidder must be able to manage and transfer its awarded NFT. Delivery uses `transferFrom`, so absence of a receiver hook alone does not establish incompatibility. No winner acceptance callback or administrator recovery authority was added; bidder integration responsibilities are documented.

### OBS-010 — Buy-now recipients are not acceptance-checked

**Implemented with accepted limitation.** [Report p. 114](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=114)

Auction delivery rejects the auction house itself as recipient. Other caller-selected contracts remain responsible for accepting and managing delivered assets; no general acceptance callback was added. The limitation is documented alongside OBS-009.

### OBS-011 — Renewed listings can keep a removed currency

**Implemented.** [Report p. 116](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=116)

`updateListing` rechecks that the selected currency is currently allowlisted. Removing a currency does not disable existing listing execution, cancellation, claims, or payout repair. This applies the admission policy to renewed listing terms without blocking existing obligations.

### OBS-012 — Whole-bitmap reads do not scale with selectable supply

**Acknowledged.** [Report p. 118](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=118)

Selectable minting is intended for relatively small collections. Whole-bitmap reads scale with configured initial supply, not minted count; bounded `isIndexMinted` reads remain available. A local cold-read benchmark for 10,000 pieces used approximately 101,309 gas and 1,344 ABI bytes, including call/result copying. No pagination or enforced size cap was added; RPC limits and gas schedules may differ.

### OBS-013 — Presale leaf documentation omits hashing steps

**Documentation updated and tested.** [Report p. 120](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=120)

The exact presale leaf encoding, recipient pre-hash, outer hash, and sorted-pair proof construction are documented in `docs/presale-merkle.md`. Independent literal vectors and real purchase tests cover ERC-721, selectable minting, ERC-1155, and incorrect recipient/allowance rejection. On-chain verifier format and existing roots are unchanged.

### OBS-014 — Callback-time updates make later listing events stale

**Implemented.** [Report p. 122](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=122)

`updatePayoutReceiver` is now `nonReentrant`, matching every other listing-state function, so no callback during listing, bidding, or topping up can change a listing between its storage write and its event. The emitted listing therefore equals storage. A callback that attempts such an update reverts: an NFT-transfer or ERC-20 top-up callback reverts the whole operation atomically, and an ETH-refund callback makes the refund fail, crediting the refunded bidder instead. Terminal events still use the final snapshot taken before deletion. Regression tests cover NFT-transfer, ETH-refund, and ERC-20 top-up callbacks.

### OBS-015 — Drop events lack round identity

**Acknowledged.** [Report p. 125](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=125)

No round IDs were added to existing drop events. Indexers must account for the existing lifecycle and event semantics. This is accepted as an observability limitation rather than an authorization change.

### OBS-016 — Deprecated sanctions oracle can return stale negatives

**Acknowledged.** [Report p. 127](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=127)

Oracle selection and freshness are protocol-owner responsibilities. The oracle can be replaced or disabled, so no provider-specific migration is hardcoded. Actual production configuration was not inspected in this review; a successful Boolean response alone does not establish that sanctions data is current.

### OBS-017 — Decay-rate NatSpec describes a Merkle root

**Documentation updated.** [Report p. 129](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=129)

Both minters' decay-rate NatSpec now describes signed seconds per minted token: negative shortens the public phase and positive extends it. Documentation includes the invalid signed-minimum value and the saturation behavior.

### OBS-018 — Callback-forwarding ERC-20 recipients fail balance checks

**Acknowledged.** [Report p. 131](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=131)

Direct ERC-20 payout balance-delta checks are retained as a safety condition. Callback-forwarding receivers that move funds before `transferFrom` returns may fail this condition, reverting the purchase atomically. Integrations must select compatible currencies and recipients; no staging custody was introduced.

### OBS-019 — Renouncing while paused permanently disables sales

**Implemented.** [Report p. 133](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=133)

All three sales contracts disable ownership renunciation, including while paused, preserving an owner capable of unpausing. Two-step transfer and cancellation of a pending transfer remain supported. This shares the guard in OBS-005.

### OBS-020 — Several terminal authority choices eliminate mint recovery

**Acknowledged with related guard.** [Report p. 135](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=135)

Collection ownership/admin handover and retention of usable authority are collection-team responsibilities. No universal recovery authority or collection-handover mechanism was added. Protocol-owner renunciation is separately disabled in all three sales contracts under OBS-005/019.

### OBS-021 — Minimum signed decay rate cannot be negated

**Implemented.** [Report p. 138](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=138)

Both minters reject `type(int256).min` during configuration and decay-rate updates with `InvalidDecayRate`. Rejected operations preserve the existing drop. Other signed values remain subject to the duration arithmetic checks.

### OBS-022 — Extreme negative rates overflow before clamping

**Implemented.** [Report p. 140](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=140)

Negative-rate adjustments compare quantity with the available duration divided by rate magnitude before multiplying. Reductions beyond the duration saturate to zero without intermediate overflow. Tests retain zero and exact-boundary behavior, supply/count accounting, and coverage of the shared mint paths.

### OBS-023 — Positive adjustments overflow duration storage

**Implemented.** [Report p. 142](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=142)

Positive duration adjustments are compared against the remaining complete-endpoint headroom before multiplication and addition, and are capped at that headroom. A mint that would extend past `uint64.max` still succeeds, with the schedule ending at the ceiling (effectively never), mirroring how negative adjustments saturate at zero. No rate, including `int256.max`, can overflow or block purchases. Covered with HEX-022 by exact-ceiling and maximum-rate regressions for both minters.

### OBS-024 — Auction-house self-destinations consume recovery rights

**Implemented.** [Report p. 144](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=144)

The auction house rejects itself at shared recipient-validation boundaries, including fee and seller payouts, NFT delivery, and funds/NFT claims. Royalties naming the auction house remain skipped. This prevents self-destinations from consuming recovery rights; no administrator rescue was added.

### OBS-025 — Mint payout receivers can be the minter itself

**Implemented.** [Report p. 146](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=146)

Both minters reject themselves as seller-payout and protocol-fee receivers. Other contract receivers remain the configuring party's responsibility. No additional per-drop custody or administrator recovery mechanism was added.

### OBS-026 — Global seller-fee changes affect active mint drops

**Acknowledged.** [Report p. 149](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=149)

The current global mint seller fee, capped at 5%, applies to active drops. Owner changes can affect seller proceeds without changing the buyer's price or round. No snapshot or collection-specific fee ceiling was added. A collection may close the drop or revoke permission, but is not guaranteed time to react before a change applies.

### OBS-027 — Late index conflicts waste more gas

**Acknowledged.** [Report p. 151](transient-labs-stacks-v2.8.0-hexwarden-audit-v1.pdf#page=151)

A conflict late in a selectable batch can consume extra gas before reverting the whole purchase. Payment and mint state roll back; transaction gas does not. The existing duplicate/index checks remain, and further early-validation optimization is deferred within the documented small-collection scope.

## Additional agreed change: configurable auction ETH payout gas

The auction house now exposes `payoutGasLimit`, initially **100,000 gas** (unchanged from the previous constant, so default behavior is the same as the audited revision), and an owner-only `setPayoutGasLimit(uint256)` setter that rejects zero and emits the previous/new values. It controls each automatic ETH payout or bid refund and can be updated while paused. Failed automatic payments retain the existing credit behavior when execution has sufficient gas to record it.

There is no hard upper cap; owner configuration remains trusted. An excessive allowance can exhaust the transaction before fallback accounting, and multiple payouts each consume their own allowance. The setter exists so the allowance can be raised or lowered if future EVM gas-schedule changes make 100,000 gas unsuitable; it is not a guarantee against all such changes. Explicit claims/retries retain the all-available-gas helper; ERC-20 transfers and mint payouts are unchanged by this setting.

## Integration changes

Consumers must update these signatures and reads:

| Contract | Updated interface |
| --- | --- |
| TLStacks721 | `waiveSellerFee(address nftAddress, uint256 expectedRound)` |
| TLStacks1155 | `waiveSellerFee(address nftAddress, uint256 tokenId, uint256 expectedRound)` |
| TLAuctionHouse | `removeProtocolFee(address nftAddress, uint256 tokenId, uint256 expectedListingId)` |
| TLAuctionHouse | New `retryPayout(address beneficiary, address currencyAddress)` |
| TLAuctionHouse | New `setPayoutGasLimit(uint256)`; read `payoutGasLimit()` instead of the former `PAYOUT_GAS_LIMIT()` getter |

Unchecked fee-waiver overloads have been removed. Integrations should handle stale-identity reverts, the five-minute top-up cutoff, stricter input/recipient validation, and disabled ownership renunciation. `NftClaimRetired` exposes retirement of a prior NFT recovery claim. Existing drop events have not gained round IDs.

## Implementation and validation references

| Area | Source and regression coverage |
| --- | --- |
| Auction lifecycle, recovery, events, and gas settings | [TLAuctionHouse.sol](../src/TLAuctionHouse.sol), [auction utilities](../src/utils/TLAuctionHouseUtils.sol), [auction edge tests](../test/edge/TLAuctionHouse.edge.t.sol), [auction tests](../test/TLAuctionHouse.t.sol) |
| Mint input validation, waivers, arithmetic, and recipient guards | [TLStacks721.sol](../src/TLStacks721.sol), [TLStacks1155.sol](../src/TLStacks1155.sol), [CommonUtils.sol](../src/utils/CommonUtils.sol), [mint edge tests](../test/edge/TLStacks.edge.t.sol) |
| Royalty schedule selection and fallback | [RoyaltyLookup.sol](../src/helpers/RoyaltyLookup.sol), [helper tests](../test/helpers/RoyaltyLookup.t.sol), [auction edge tests](../test/edge/TLAuctionHouse.edge.t.sol) |
| Presale encoding | [Merkle documentation](../docs/presale-merkle.md), [literal test vectors](../test/utils/presale-vectors.json), [ERC-721 tests](../test/TLStacks721.t.sol), [ERC-1155 tests](../test/TLStacks1155.t.sol) |

The final implementation passed `FOUNDRY_PROFILE=ci forge test --offline`: **349 tests across 14 suites, zero failures or skips**, with 1,024 runs per fuzz test and 256 invariant runs at depth 100. `forge build --offline` and `forge fmt --check` also passed; the build retains existing lint advisories. Repository whitespace validation passed with `git diff --check`.

Deployment-size regressions cover all three sales contracts. With Solidity 0.8.30 and the repository's optimizer setting of 20,000 runs:

| Contract | Runtime bytes | Headroom below 24,576 bytes |
| --- | ---: | ---: |
| TLAuctionHouse | 23,768 | 808 |
| TLStacks721 | 23,800 | 776 |
| TLStacks1155 | 20,783 | 3,793 |

Auction-house code-size headroom is limited, so the regression should remain part of validation for subsequent changes. These results are local implementation checks, not deployed-system verification. The auditor's separately supplied executable PoCs were not run; regression coverage uses repository tests. Production oracle configuration and external collection/currency behavior were not independently verified.

Please verify the implemented remediations against the accompanying source changes and record the acknowledged risks and documentation changes in the final audit disposition.

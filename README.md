# Transient Labs Stacks Protocol
The Stacks Protocol consists of sales contracts for the Transient Labs ecosystems. Sales comprise of mints, auctions, and buy nows. More can be added in the future as well.

## Mints
Two contracts for minting new NFTs to ERC-721 and ERC-1155 contracts. Meant to work specifically with Transient Labs contracts but works for any contract that employs the proper function signature for `externalMint` (different signature for 721 vs 1155).

The mint contracts are
- `TLStacks721.sol`
- `TLStacks1155.sol`

### Features
- multi-tenant sales which keeps NFT contracts lighter weight with less code
- implements a flat buyers fee in ETH per NFT minted on ETH drops. ERC-20 drops charge no ETH, so a purchase only needs the drop currency (friendly to cross-chain fillers).
- seller fee as a percentage of the sale, with separate rates for ETH and ERC-20 drops, each capped at 5% (`MAX_SELLER_FEE_BPS`)
- the contract owner can waive the seller fee for a drop. The waiver is tied to the drop round, so it resets when the drop is closed or reconfigured.
- configurable for any allowlisted ERC-20 token (the contract owner manages the allowlist; native currency is always allowed)
- drop admins can decrease a live drop's total supply (never below the number already minted, and never above the configured supply)
- velocity/marathon mint: the duration of the open edition decreases (velocity) or increases (marathon) with each mint
- selectable mint (ERC-721 only): buyers pick which 0-based pieces of the drop they mint, and each piece can only be minted once per drop round
- only the NFT contract owner or admins can configure/alter/cancel a mint
- purchases specify the expected currency, max cost per token, and drop round, so buyers are protected if a drop's price, currency, or phase changes, or the drop is closed and reconfigured (e.g. with new art), while their transaction is pending

## Auction House
A contract for auctions and/or buy nows for minted ERC-721 tokens. Works for any ERC-721 compliant token in existence.

The auction house contract is `TLAuctionHouse.sol`

### Features
- protocol fee as a percentage of the sale, charged to the seller
- auction durations extended for any bids that come in the last five minutes
- listings can be scheduled ahead of time
- configurable for any allowlisted ERC-20 token (the contract owner manages the allowlist; native currency is always allowed)
- respects royalties on secondary sales (if configured on the token)
- listing types
    - Scheduled auction
    - Reserve auction
    - Reserve auction + buy now
    - Buy now
    - Private sale (fixed price, and the NFT is always delivered to the recipient set by the seller, though anyone can pay)
- multiple NFTs can be listed in one transaction via `batchList` (if any listing fails, the whole batch reverts)
- only the NFT owner can configure or cancel an listing
- sellers can update a listing via `updateListing` instead of canceling and relisting, which changes everything except the listing type and currency. Updates aren't allowed once an auction has been bid on, and each update gets a new listing id so pending bids and buys signed against the old terms revert
- sellers can change the payout receiver at any time before settlement via `updatePayoutReceiver`, which keeps the listing id since bidders' terms don't change
- the highest bidder can add to their bid via `topUpBid`; top ups never extend the auction, so the highest bidder can't keep an auction open indefinitely
- the NFT is always delivered to the buyer before funds are released to the seller; settlement either fully completes or reverts, and anyone can settle an ended auction
- if an auction can't be settled (e.g. a broken NFT contract or a sanctioned party), the seller or highest bidder can cancel it via `cancelUnsettledAuction` once the settlement grace period (7 days after the auction ends) has passed, which credits the bid to the bidder (`claimableFunds`) and holds the NFT for the seller (`claimableNft`)
- payouts that fail (reverting receivers, ERC-20 blocklists, sanctioned addresses) are credited and can be pulled to any address via `claimFunds`
- NFTs from canceled unsettled auctions are held for the seller and can be pulled via `claimNft`; anything owed to a sanctioned address stays frozen until the address is no longer sanctioned
- bids specify the expected listing id and currency, and buy nows specify the expected currency and max price, to guard against front-running (e.g. a seller delisting and relisting with a longer auction duration while a bid is pending)
- the minimum next bid is the current bid plus 5%, rounded up

### Trust Assumptions & Known Limitations
- **ERC-20 allowlist:** only standard ERC-20 tokens should be allowed. Rebasing, fee-on-transfer, and other tokens whose balances can change outside of transfers are not supported. Incoming transfers are checked for the full amount, but escrow and payouts assume balances held by the contract never change on their own (a negative rebase would leave escrowed bids and `claimableFunds` underfunded) and don't account for fees on outgoing transfers. Low-decimal tokens should also be avoided so that bid increments stay meaningful.
- **Primary vs. secondary sales:** a sale is treated as primary (no royalties) when the seller matches the address returned by the `creatorLookup` helper. The default `CreatorLookup` returns the collection's current `owner`, which fits single-creator collections like Transient Labs creator contracts. For multi-creator collections, collections whose ownership has changed hands, or royalties paid to someone other than the collection owner (e.g. a collaborator split), a sale by the collection owner skips royalties. If the lookup is unset or fails, the sale is treated as secondary.

## Deployments
Contracts are deployed to the same address cross-chain using CREATE2. In doing such, constructor args have to be set to default values and then changed after deployment. Contracts are initially deployed with an EOA as the owner until initializations are made, then subsequently contract ownership is transferred to multi-sigs. Ownership transfers are two-step (`Ownable2Step`), so the multi-sig must call `acceptOwnership` to complete the transfer.

### Sanctions Oracle
https://go.chainalysis.com/chainalysis-oracle-docs.html

## Disclaimer
While best efforts have gone into developing, testing, and peer reviewing these contracts, unexpected behavior may be present in the contracts under certain conditions. Transient Labs has a bug bounty program to preemptively squash any bugs found in our contracts.

This codebase is provided on an "as is" and "as available" basis.

We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

## License
This code is copyright Transient Labs, Inc 2026 and is licensed under the MIT license.
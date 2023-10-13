# Transient Labs Stacks Protocol
The Stacks Protocol consists of sales contracts for the Transient Labs ecosystems. Sales comprise of mints, auctions, and buy nows. More can be added in the future as well.

## Mints
Two contracts for minting new NFTs to ERC-721 and ERC-1155 contracts. Meant to work specifically with Transient Labs contracts but works for any contract that employs the proper function signature for `externalMint` (different signature for 721 vs 1155).

The mint contracts are
- `TLStacks721.sol`
- `TLStacks1155.sol`

### Features
- multi-tenant sales which keeps NFT contracts lighter weight with less code
- implements a flat buyers fee in ETH per NFT minted
- configurable for any ERC-20 token
- velocity/marathon mint: the duration of the open edition decreases (velocity) or increases (marathon) with each mint
- only the NFT contract owner or admins can configure/alter/cancel a mint

## Auction House
A contract for reserve auctions and/or buy nows for minted ERC-721 tokens. Works for any ERC-721 token in existence.

The auction house contract is `TLAuctionHouse.sol`

### Features
- implements a capped percentage buyers fee
- configurable for any ERC-20 token
- ALWAYS respects royalties if configured on the Royalty Registry
- Reserve auction can be configured ahead of time and have any duration desired
- Reserve auction and buy now can be listed at the same time and if either is hit first, the other is canceled automatically
- Only the NFT owner can configure or cancel an auction/buy now (this is true even when the NFT transfers hands outside of this contract)
- Buy Nows can be configured ahead of time as well

## Safety
- If you have a listing on the Auction House and sell the token on another marketplace, beware that your listing on the Auction House is stale and if the NFT returns to your wallet at some point, the listing becomes valid. In the real world, this doesn't seem to occur very often, yet, you'll want to cancel your listing in this scenario.

## Disclaimer
While best efforts have gone into developing, testing, and peer reviewing these contracts, unexpected behavior may be present in the contracts under certain conditions. Transient Labs is setting up a bug bounty program on ImmuneFi to preemptively squash any bugs found in our contracts.

This codebase is provided on an "as is" and "as available" basis.

We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

## License
This code is copyright Transient Labs, Inc 2023 and is licensed under the MIT license.
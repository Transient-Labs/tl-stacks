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
A contract for auctions and/or buy nows for minted ERC-721 tokens. Works for any ERC-721 compliant token in existence.

The auction house contract is `TLAuctionHouse.sol`

### Features
- protocol fee as a percentage of the sale, charged to the seller
- auction durations extended for any bids that come in the last five minutes
- listings can be scheduled ahead of time
- configurable for any ERC-20 token
- respects royalties on secondary sales (if configured on the token)
- listing types
    - Scheduled auction
    - Reserve auction
    - Reserve auction + buy now
    - Buy now
- only the NFT owner can configure or cancel an listing

## Deployments
Contracts are deployed to the same address cross-chain using CREATE2. In doing such, constructor args have to be set to default values and then changed after deployment. Contracts are initially deployed with an EOA as the owner until initializations are made, then subsequently contract ownership is transferred to multi-sigs.

### WETH Addresses
Ethereum: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
Sepolia: `0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9`
Arbitrum: `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1`
Arbitrum-Sepolia: `0x980B62Da83eFf3D4576C647993b0c1D7faf17c73`
Base: `0x4200000000000000000000000000000000000006`
Base-Sepolia: `0x4200000000000000000000000000000000000006`
Shape: `0x4200000000000000000000000000000000000006`
Shape-Sepolia: `0x4200000000000000000000000000000000000006`

### Sanctions Oracle
https://go.chainalysis.com/chainalysis-oracle-docs.html

## Disclaimer
While best efforts have gone into developing, testing, and peer reviewing these contracts, unexpected behavior may be present in the contracts under certain conditions. Transient Labs has a bug bounty program to preemptively squash any bugs found in our contracts.

This codebase is provided on an "as is" and "as available" basis.

We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

## License
This code is copyright Transient Labs, Inc 2024 and is licensed under the MIT license.
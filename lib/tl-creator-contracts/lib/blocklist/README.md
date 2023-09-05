# Transient Labs BlockList
BlockList is a smart contract utility that can be utilized to block approvals of marketplaces that creators don't want their work trading on.

## 1. Problem Statement
It's a race to zero in terms of marketplace fees, but in an effort to keep cash flow, some marketplaces have decided forego creator feeds. This hurts creators an incredible amount and we believe that creators should have the option to block having their art listed on these platforms.

## 2. Our Solution
This is why we created BlockList. The `BlockList.sol` contract can be inherited by nft contracts and the modifier `notBlocked(address)` can be used on `setApprovalForAll` and `approve` functions in ERC-721 and/or ERC-1155 contracts. We have included a sample implementation of both in this repo.

Theoretically, this modifier could be applied to other functions, but we HIGHLY advise against this. Applying this logic to transfer functions introduces slight vulnerabilties that should be avoided. 

To implement BlockList, simply inherit `BlockList.sol`.

## 3. Why Not An Allowlist Method Instead?
To keep composability with new standards and reduced interaction needed in the future, BlockList is implemented as a blocker rather than an allower. We welcome feedback on this.

## Deployments
See https://docs.transientlabs.xyz/blocklist/implementation for the latest deployments

## Usage
When cloning this repo, the proper way to install or update the submodules installed with foundry is to run `make remove && make install` or `make update`. 

Other methods of installing, such as `forge install` or `forge update` are not guaranteed to install the proper modules and you run a risk of installing modules with breaking changes.

## Disclaimer
We have verified with OpenSea engineers that BlockList is fully compatible with their royalties enforcement system, as of 11/7/2022.

This codebase is provided on an "as is" and "as available" basis.

We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

## License
This code is copyright Transient Labs, Inc 2023 and is licensed under the MIT license.
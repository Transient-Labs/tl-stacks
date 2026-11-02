# Presale Merkle format

Both minters, including regular and selectable ERC-721 purchases, use the same existing format. This documentation does not change valid roots or proofs. Eligibility belongs to the NFT recipient, which can differ from the payer.

## Leaf encoding

```solidity
bytes32 recipientHash = keccak256(abi.encode(recipient)); // address: 32-byte ABI word
bytes32 innerHash = keccak256(abi.encode(recipientHash, allowance)); // bytes32, uint256
bytes32 leaf = keccak256(bytes.concat(innerHash)); // hash the raw 32 bytes once more
```

Use Ethereum Keccak-256, not SHA3-256. `abi.encode(recipient)` pads the address to 32 bytes; hashing its packed 20 bytes produces a different leaf. The allowance is an unsigned 256-bit integer. Do not omit the recipient pre-hash or the outer hash. Neither the payer, NFT address, token ID, nor round is part of the leaf; each configured drop supplies its own root.

## Tree and proof conventions

For every proof sibling, concatenate the two raw `bytes32` values in ascending numeric/byte order, then Keccak-hash the 64 bytes. Repeat from leaf to root. Proofs contain siblings in traversal order; they do not include the leaf or root. No left/right flag is supplied.

The verifier does not mandate leaf ordering, tree balancing, or an odd-node convention. The root builder and proof generator must use the same tree. For an OpenZeppelin-style standard tree, provide `[recipientHash, allowance]` with ABI types `[bytes32, uint256]`; its standard double-hashed leaf supplies the inner and outer hashes above. Supplying `[recipient, allowance]` instead is incompatible. Keep one allowance entry per recipient per drop to avoid ambiguous overlapping proofs.

## Fixed two-leaf vector

The complete intermediate hashes are in [presale-vectors.json](../test/utils/presale-vectors.json). They were generated independently of the Solidity purchase helper with Foundry's `cast abi-encode` and `cast keccak`.

| Recipient | Allowance | Leaf |
| --- | --- | --- |
| `0x1111111111111111111111111111111111111111` | 2 | `0xe9ca91c0161bdc8418896a6f054e74a33e73033d10bd7729424ae950fd14bd63` |
| `0x2222222222222222222222222222222222222222` | 3 | `0x2aef90b6985a8b20b48d621d20393a6b22ec2a2fbd4d3b841c860aedcb8aa754` |

Root: `0xa0a141551de2692f573b52765fbbc7e60173da2368b89948bae522a7c2cce0ff`.

The proof for either entry is a one-element array containing the other entry's leaf. `test_pending_merkleVectorRegular`, `test_pending_merkleVectorSelected`, and the ERC-1155 `test_pending_merkleVector` submit literal vectors to the real purchase paths and reject mutated allowances/recipients. A single-leaf tree uses the leaf itself as root and an empty proof.

To reproduce the first leaf with Foundry:

```sh
recipient_hash=$(cast keccak "$(cast abi-encode 'f(address)' 0x1111111111111111111111111111111111111111)")
inner_hash=$(cast keccak "$(cast abi-encode 'f(bytes32,uint256)' "$recipient_hash" 2)")
cast keccak "$inner_hash"
```

# Run 1 — solidity-auditor

<!--RUN pass=1 of=3 stamp=20260926-013456 sha=4085b92 agents=12/12-->

Pass 1 of 3 · 2026-09-26 · `4085b92` · 12/12 agents returned.

## Findings

<!--F key=tlstacks721|purchaseselected|unauthorized-allocation-consumption conf=90 kind=FINDING agents=1-->

[90] **A caller consumes another user's selected mint allowance**

`TLStacks721.purchaseSelected` · Confidence: 90

**Description**
An attacker can use a user's presale proof to mint an unwanted index to that user, so the user loses their chosen index.

**Fix**

```diff
     ) external payable nonReentrant whenNotPaused {
+        require(msg.sender == recipient, "recipient must call");
         (Drop memory drop, DropPhase dropPhase, uint256 cost) = _validatePurchase(
```

<!--/F-->

<!--F key=tlstacks721|-settleup|seller-fee-rounds-to-zero conf=90 kind=FINDING agents=2-->

[90] **Split purchases reduce the seller fee to zero**

`TLStacks721._settleUp` · Confidence: 90

**Description**
A seller can split low decimal token mints into small purchases, so each fee rounds to zero and the protocol loses its share.

**Fix**

```diff
+import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
-            sellerFee = totalSale * (isEth ? ethSellerFeeBps : erc20SellerFeeBps) / BASIS;
+            sellerFee = Math.mulDiv(totalSale, isEth ? ethSellerFeeBps : erc20SellerFeeBps, BASIS, Math.Rounding.Ceil);
```

<!--/F-->

<!--F key=tlstacks1155|-settleup|seller-fee-rounds-to-zero conf=90 kind=FINDING agents=2-->

[90] **Split purchases reduce the seller fee to zero**

`TLStacks1155._settleUp` · Confidence: 90

**Description**
A seller can split low decimal token mints into small purchases, so each fee rounds to zero and the protocol loses its share.

**Fix**

```diff
+import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
-            sellerFee = totalSale * (isEth ? ethSellerFeeBps : erc20SellerFeeBps) / BASIS;
+            sellerFee = Math.mulDiv(totalSale, isEth ? ethSellerFeeBps : erc20SellerFeeBps, BASIS, Math.Rounding.Ceil);
```

<!--/F-->

<!--F key=tlauctionhouse|-completesale|post-transfer-royalty-lookup conf=75 kind=FINDING agents=2-->

[75] **The sale pays royalties to the buyer for holder based NFTs**

`TLAuctionHouse._completeSale` · Confidence: 75

**Description**
The sale transfers the NFT before it reads royalties, so a token that pays its current owner sends the buyer the royalty share.

**Fix**

```diff
-        _transferNft(nftAddress, tokenId, address(this), recipient);
+        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts) =
+            _getSaleRoyalties(nftAddress, tokenId, value);
+        _transferNft(nftAddress, tokenId, address(this), recipient);
```

<!--/F-->

## Leads

<!--F key=tlstacks721|-settleup|sanctioned-fee-payout kind=LEAD agents=2-->

- **The protocol can pay a receiver after sanctions change** — `TLStacks721._settleUp` — Code smells: The fee receiver is checked when set, but the purchase checks only the buyer, mint recipient, and seller payout receiver. A buyer can pay a fee to a receiver that the oracle sanctioned after setup; the impact beyond the compliance rule needs review.

<!--/F-->

<!--F key=tlstacks1155|-settleup|sanctioned-fee-payout kind=LEAD agents=2-->

- **The protocol can pay a receiver after sanctions change** — `TLStacks1155._settleUp` — Code smells: The fee receiver is checked when set, but the purchase checks only the buyer, mint recipient, and seller payout receiver. A buyer can pay a fee to a receiver that the oracle sanctioned after setup; the impact beyond the compliance rule needs review.

<!--/F-->

<!--F key=tlauctionhouse|getroyalty|royalty-view-settlement-divergence kind=LEAD agents=1-->

- **The displayed royalty can differ from the sale royalty** — `TLAuctionHouse.getRoyalty` — Code smells: The view uses `getRoyaltyView`, while settlement uses `getRoyalty` on an external lookup. A buyer can read one royalty amount before a sale, but the configured engine may return another amount during settlement.

<!--/F-->

<!--F key=royaltylookup|getroyalty|failed-engine-skips-erc2981 kind=LEAD agents=1-->

- **A failed royalty engine skips ERC-2981 data** — `RoyaltyLookup.getRoyalty` — Code smells: A failed or malformed engine response returns empty arrays even when the NFT provides ERC-2981 data. A seller receives the royalty share if the configured engine fails; attacker control of that failure remains unverified.

<!--/F-->

<!--F key=tlstacks721|purchase|velocity-batch-time-bypass kind=LEAD agents=1-->

- **A batch mint can pass the sale end time** — `TLStacks721.purchase` — Code smells: The function checks the phase once, then `_updateDropState` reduces the duration for every token in the batch. A buyer can mint a batch that ends a velocity drop, but the intended time rule for each token remains unclear.

<!--/F-->

<!--F key=tlstacks1155|purchase|velocity-batch-time-bypass kind=LEAD agents=1-->

- **A batch mint can pass the sale end time** — `TLStacks1155.purchase` — Code smells: The function checks the phase once, then `_updateDropState` reduces the duration for every token in the batch. A buyer can mint a batch that ends a velocity drop, but the intended time rule for each token remains unclear.

<!--/F-->

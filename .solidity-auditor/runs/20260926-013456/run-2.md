# Run 2 — solidity-auditor

<!--RUN pass=2 of=3 stamp=20260926-013456 sha=4085b92 agents=12/12-->

Pass 2 of 3 · 2026-09-26 · `4085b92` · 12/12 agents returned.

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

<!--F key=tlauctionhouse|bid|sanctioned-seller-bid conf=75 kind=FINDING agents=1-->

[75] **A bid locks funds for a seller who cannot settle**

`TLAuctionHouse.bid` · Confidence: 75

**Description**
The auction accepts a bid after the seller becomes sanctioned, but settlement rejects that seller and holds the bidder's funds through the grace period.

**Fix**

```diff
         Listing memory listing = _listings[nftAddress][tokenId];
+        if (_isSanctioned(listing.seller)) revert SanctionedAddress();
         uint256 previousBid = listing.highestBid;
```

<!--/F-->

<!--F key=tlauctionhouse|topupbid|sanctioned-seller-top-up conf=75 kind=FINDING agents=1-->

[75] **A top up locks more funds after the seller is sanctioned**

`TLAuctionHouse.topUpBid` · Confidence: 75

**Description**
The auction accepts more funds after the seller becomes sanctioned, but settlement rejects that seller and holds the added funds through the grace period.

**Fix**

```diff
         Listing memory listing = _listings[nftAddress][tokenId];
+        if (_isSanctioned(listing.seller)) revert SanctionedAddress();
 
         // check the listing type
```

<!--/F-->

<!--F key=tlstacks721|purchase|velocity-batch-time-bypass conf=90 kind=FINDING agents=4-->

[90] **A batch mints tokens after a velocity sale ends**

`TLStacks721.purchase` · Confidence: 90

**Description**
A buyer can mint extra tokens near a velocity sale's end because the contract checks time once before it shortens the sale for the batch.

**Fix**

```diff
         if (drop.dropType == DropType.SELECTABLE) revert NotAllowedForSelectableDrops();
+        if (drop.dropType == DropType.VELOCITY && drop.decayRate < 0 && numberToMint > 1) {
+            uint256 reduction = uint256(-drop.decayRate) * (numberToMint - 1);
+            if (reduction >= drop.startTime + drop.publicDuration - block.timestamp) revert YouShallNotMint();
+        }
```

<!--/F-->

<!--F key=tlstacks1155|purchase|velocity-batch-time-bypass conf=90 kind=FINDING agents=4-->

[90] **A batch mints units after a velocity sale ends**

`TLStacks1155.purchase` · Confidence: 90

**Description**
A buyer can mint extra units near a velocity sale's end because the contract checks time once before it shortens the sale for the batch.

**Fix**

```diff
         if (numberToMint > numberCanMint) revert CannotMintMoreThanAllowed();
+        if (drop.dropType == DropType.VELOCITY && drop.decayRate < 0 && numberToMint > 1) {
+            uint256 reduction = uint256(-drop.decayRate) * (numberToMint - 1);
+            if (reduction >= drop.startTime + drop.publicDuration - block.timestamp) revert YouShallNotMint();
+        }
```

<!--/F-->

<!--F key=tlstacks721|-settleup|sanctioned-fee-payout conf=75 kind=FINDING agents=4-->

[75] **The protocol pays a newly sanctioned fee receiver**

`TLStacks721._settleUp` · Confidence: 75

**Description**
A buyer can mint after the fee receiver becomes sanctioned, and the contract sends that receiver the protocol fee.

**Fix**

```diff
         uint256 sellerProceeds = totalSale - sellerFee;
+        if ((isEth ? numberToMint * protocolFee + sellerFee : sellerFee) != 0
+            && _isSanctioned(protocolFeeReceiver)) revert SanctionedAddress();
 
         // payout the mint and protocol fees
```

<!--/F-->

<!--F key=tlstacks1155|-settleup|sanctioned-fee-payout conf=75 kind=FINDING agents=4-->

[75] **The protocol pays a newly sanctioned fee receiver**

`TLStacks1155._settleUp` · Confidence: 75

**Description**
A buyer can mint after the fee receiver becomes sanctioned, and the contract sends that receiver the protocol fee.

**Fix**

```diff
         uint256 sellerProceeds = totalSale - sellerFee;
+        if ((isEth ? numberToMint * protocolFee + sellerFee : sellerFee) != 0
+            && _isSanctioned(protocolFeeReceiver)) revert SanctionedAddress();
 
         // payout the mint and protocol fees
```

<!--/F-->

## Leads

<!--F key=tlauctionhouse|getroyalty|royalty-view-settlement-divergence kind=LEAD agents=1-->

- **The displayed royalty can differ from the sale royalty** — `TLAuctionHouse.getRoyalty` — Code smells: The view uses `getRoyaltyView`, while settlement uses `getRoyalty` on an external lookup. A buyer can read one royalty amount before a sale, but the configured engine may return another amount during settlement.

<!--/F-->

<!--F key=royaltylookup|getroyalty|failed-engine-skips-erc2981 kind=LEAD agents=1-->

- **A failed royalty engine skips ERC-2981 data** — `RoyaltyLookup.getRoyalty` — Code smells: A failed or malformed engine response returns empty arrays even when the NFT provides ERC-2981 data. A seller receives the royalty share if the configured engine fails; attacker control of that failure remains unverified.

<!--/F-->

<!--F key=tlauctionhouse|setroyaltylookup|unsettled-sale-royalty-redirection kind=LEAD agents=2-->

- **A lookup change can alter a committed seller payout** — `TLAuctionHouse.setRoyaltyLookup` — Code smells: The owner may replace the royalty helper after a winning bid, and settlement uses the new helper. A new helper can move up to 10% of the sale value from the seller; this path depends on owner control.

<!--/F-->

<!--F key=tlauctionhouse|cancelunsettledauction|valid-auction-cancellation kind=LEAD agents=2-->

- **A valid auction can be canceled after the grace period** — `TLAuctionHouse.cancelUnsettledAuction` — Code smells: The function checks elapsed time but does not test whether settlement fails. Either party can cancel an otherwise valid auction after seven days if nobody settles it; the intended binding rule is unclear.

<!--/F-->

<!--F key=tlstacks721|purchase|unauthorized-allocation-consumption kind=LEAD agents=2-->

- **A gift mint uses the recipient's allowance** — `TLStacks721.purchase` — Code smells: Any payer can mint to another address and use that recipient's quota. The recipient gets the NFT, but the value of a later sequential metadata slot remains unverified.

<!--/F-->

<!--F key=tlstacks1155|purchase|unauthorized-allocation-consumption kind=LEAD agents=2-->

- **A gift mint uses the recipient's allowance** — `TLStacks1155.purchase` — Code smells: Any payer can mint to another address and use that recipient's quota. The recipient gets the tokens, and material loss beyond a lost choice remains unverified.

<!--/F-->

# 🔐 Security Review — tl-sales-contracts

---

## Scope

|  |  |
| --- | --- |
| **Mode** | default |
| **Files reviewed** | `src/utils/TLStacks721Utils.sol` · `src/utils/TLAuctionHouseUtils.sol` · `src/utils/CommonUtils.sol`<br>`src/utils/TLStacks1155Utils.sol` · `src/TLAuctionHouse.sol` · `src/lib/IChainalysisSanctionsOracle.sol`<br>`src/lib/CurrencyAllowlist.sol` · `src/lib/SanctionsCompliance.sol` · `src/lib/TransferHelper.sol`<br>`src/TLStacks1155.sol` · `src/helpers/IRoyaltyLookup.sol` · `src/helpers/RoyaltyLookup.sol`<br>`src/helpers/CreatorLookup.sol` · `src/helpers/ICreatorLookup.sol` · `src/helpers/IRoyaltyEngineV1.sol`<br>`src/TLStacks721.sol` · `script/Deploy.s.sol` |
| **Confidence threshold (1-100)** | 75 |
| **Passes** | 3 |
| **Memory** | 0 records before this scan · 18 after · `4085b92` |

---

## Findings

[90] **1. A seller cancels a valid winning auction after seven days**

`TLAuctionHouse.cancelUnsettledAuction` · Confidence: 90 · seen in 2/3 runs · NEW

**Description**
A seller can cancel a healthy auction after seven days, reclaim the NFT, and deny the winning bidder the agreed purchase.

**Fix**

```diff
-        if (msg.sender != listing.seller && msg.sender != listing.highestBidder) revert NotSellerOrBidder();
+        if (msg.sender != listing.seller && msg.sender != listing.highestBidder) revert NotSellerOrBidder();
+        if (!_settlementFailureRecorded[listing.id] && !_bothPartiesApproved[listing.id]) revert AuctionStillSettleable();
```

---

[90] **2. Split purchases reduce the seller fee to zero**

`TLStacks1155._settleUp` · Confidence: 90 · seen in 3/3 runs · NEW

**Description**
A seller can split low decimal token mints into small purchases, so each fee rounds to zero and the protocol loses its share.

**Fix**

```diff
+import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
-            sellerFee = totalSale * (isEth ? ethSellerFeeBps : erc20SellerFeeBps) / BASIS;
+            sellerFee = Math.mulDiv(totalSale, isEth ? ethSellerFeeBps : erc20SellerFeeBps, BASIS, Math.Rounding.Ceil);
```

---

[90] **3. A batch mints units after a velocity sale ends**

`TLStacks1155.purchase` · Confidence: 90 · seen in 3/3 runs · NEW

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

---

[90] **4. Split purchases reduce the seller fee to zero**

`TLStacks721._settleUp` · Confidence: 90 · seen in 3/3 runs · NEW

**Description**
A seller can split low decimal token mints into small purchases, so each fee rounds to zero and the protocol loses its share.

**Fix**

```diff
+import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
-            sellerFee = totalSale * (isEth ? ethSellerFeeBps : erc20SellerFeeBps) / BASIS;
+            sellerFee = Math.mulDiv(totalSale, isEth ? ethSellerFeeBps : erc20SellerFeeBps, BASIS, Math.Rounding.Ceil);
```

---

[90] **5. A caller consumes another user's selected mint allowance**

`TLStacks721.purchaseSelected` · Confidence: 90 · seen in 3/3 runs · NEW

**Description**
An attacker can use a user's presale proof to mint an unwanted index to that user, so the user loses their chosen index.

**Fix**

```diff
     ) external payable nonReentrant whenNotPaused {
+        require(msg.sender == recipient, "recipient must call");
         (Drop memory drop, DropPhase dropPhase, uint256 cost) = _validatePurchase(
```

---

[90] **6. A batch mints tokens after a velocity sale ends**

`TLStacks721.purchase` · Confidence: 90 · seen in 3/3 runs · NEW

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

---

[75] **7. The sale pays royalties to the buyer for holder based NFTs**

`TLAuctionHouse._completeSale` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
The sale transfers the NFT before it reads royalties, so a token that pays its current owner sends the buyer the royalty share.

**Fix**

```diff
-        _transferNft(nftAddress, tokenId, address(this), recipient);
+        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts) =
+            _getSaleRoyalties(nftAddress, tokenId, value);
+        _transferNft(nftAddress, tokenId, address(this), recipient);
```

---

[75] **8. A bid locks funds for a seller who cannot settle**

`TLAuctionHouse.bid` · Confidence: 75 · seen in 2/3 runs · NEW

**Description**
The auction accepts a bid after the seller becomes sanctioned, but settlement rejects that seller and holds the bidder's funds through the grace period.

**Fix**

```diff
         Listing memory listing = _listings[nftAddress][tokenId];
+        if (_isSanctioned(listing.seller)) revert SanctionedAddress();
         uint256 previousBid = listing.highestBid;
```

---

[75] **9. The owner changes primary sale status after a bid**

`TLAuctionHouse.setCreatorLookup` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
The owner can change the creator helper after a bid, so settlement can charge a royalty that the seller did not face when bidding started.

**Fix**

```diff
 function setCreatorLookup(address newCreatorLookupAddress) external onlyOwner {
+    if (_activeBidCount != 0) revert ActiveAuction();
     address prevCreatorLookup = address(creatorLookup);
```

---

[75] **10. The owner raises the fee after a bid**

`TLAuctionHouse.setProtocolFeeSettings` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
The owner can raise the protocol fee after a bid, so the seller loses up to 5% of the committed sale price.

**Fix**

```diff
 function setProtocolFeeSettings(address newProtocolFeeReceiver, uint256 newProtocolFeeBps) external onlyOwner {
+    if (_activeBidCount != 0) revert ActiveAuction();
     if (!_isValidRecipient(newProtocolFeeReceiver)) revert InvalidRecipient();
```

---

[75] **11. The owner changes royalty recipients after a bid**

`TLAuctionHouse.setRoyaltyLookup` · Confidence: 75 · seen in 2/3 runs · NEW

**Description**
The owner can replace the royalty helper after a bid, so settlement can send up to 10% of the seller's proceeds to a new recipient.

**Fix**

```diff
 function setRoyaltyLookup(address newRoyaltyLookupAddress) external onlyOwner {
+    if (_activeBidCount != 0) revert ActiveAuction();
     address prevRoyaltyLookup = address(royaltyLookup);
```

---

[75] **12. A top up locks more funds after the seller is sanctioned**

`TLAuctionHouse.topUpBid` · Confidence: 75 · seen in 2/3 runs · NEW

**Description**
The auction accepts more funds after the seller becomes sanctioned, but settlement rejects that seller and holds the added funds through the grace period.

**Fix**

```diff
         Listing memory listing = _listings[nftAddress][tokenId];
+        if (_isSanctioned(listing.seller)) revert SanctionedAddress();
 
         // check the listing type
```

---

[75] **13. The protocol pays a newly sanctioned fee receiver**

`TLStacks1155._settleUp` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
A buyer can mint after the fee receiver becomes sanctioned, and the contract sends that receiver the protocol fee.

**Fix**

```diff
         uint256 sellerProceeds = totalSale - sellerFee;
+        if ((isEth ? numberToMint * protocolFee + sellerFee : sellerFee) != 0
+            && _isSanctioned(protocolFeeReceiver)) revert SanctionedAddress();
 
         // payout the mint and protocol fees
```

---

[75] **14. The protocol pays a newly sanctioned fee receiver**

`TLStacks721._settleUp` · Confidence: 75 · seen in 3/3 runs · NEW

**Description**
A buyer can mint after the fee receiver becomes sanctioned, and the contract sends that receiver the protocol fee.

**Fix**

```diff
         uint256 sellerProceeds = totalSale - sellerFee;
+        if ((isEth ? numberToMint * protocolFee + sellerFee : sellerFee) != 0
+            && _isSanctioned(protocolFeeReceiver)) revert SanctionedAddress();
 
         // payout the mint and protocol fees
```

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [90] | A seller cancels a valid winning auction after seven days |
| 2 | [90] | Split purchases reduce the seller fee to zero |
| 3 | [90] | A batch mints units after a velocity sale ends |
| 4 | [90] | Split purchases reduce the seller fee to zero |
| 5 | [90] | A caller consumes another user's selected mint allowance |
| 6 | [90] | A batch mints tokens after a velocity sale ends |
| 7 | [75] | The sale pays royalties to the buyer for holder based NFTs |
| 8 | [75] | A bid locks funds for a seller who cannot settle |
| 9 | [75] | The owner changes primary sale status after a bid |
| 10 | [75] | The owner raises the fee after a bid |
| 11 | [75] | The owner changes royalty recipients after a bid |
| 12 | [75] | A top up locks more funds after the seller is sanctioned |
| 13 | [75] | The protocol pays a newly sanctioned fee receiver |
| 14 | [75] | The protocol pays a newly sanctioned fee receiver |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **A failed royalty engine skips ERC-2981 data** — `RoyaltyLookup.getRoyalty` · seen in 3/3 runs · NEW — Code smells: A failed or malformed engine response returns empty arrays even when the NFT provides ERC-2981 data. A seller receives the royalty share if the configured engine fails; attacker control of that failure remains unverified.
- **The displayed royalty can differ from the sale royalty** — `TLAuctionHouse.getRoyalty` · seen in 3/3 runs · NEW — Code smells: The view uses `getRoyaltyView`, while settlement uses `getRoyalty` on an external lookup. A buyer can read one royalty amount before a sale, but the configured engine may return another amount during settlement.
- **A gift mint uses the recipient's allowance** — `TLStacks1155.purchase` · seen in 2/3 runs · NEW — Code smells: Any payer can mint to another address and use that recipient's quota. The recipient gets the tokens, and material loss beyond a lost choice remains unverified.
- **A gift mint uses the recipient's allowance** — `TLStacks721.purchase` · seen in 2/3 runs · NEW — Code smells: Any payer can mint to another address and use that recipient's quota. The recipient gets the NFT, but the value of a later sequential metadata slot remains unverified.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)

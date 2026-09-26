# 🔐 Security Review — tl-sales-contracts

---

## Scope

|  |  |
| --- | --- |
| **Mode** | default |
| **Files reviewed** | `./script/Deploy.s.sol` · `./src/utils/TLStacks721Utils.sol` · `./src/utils/TLAuctionHouseUtils.sol`<br>`./src/utils/CommonUtils.sol` · `./src/utils/TLStacks1155Utils.sol` · `./src/TLAuctionHouse.sol`<br>`./src/TLStacks1155.sol` · `./src/helpers/IRoyaltyLookup.sol` · `./src/helpers/RoyaltyLookup.sol`<br>`./src/helpers/CreatorLookup.sol` · `./src/helpers/ICreatorLookup.sol` · `./src/helpers/IRoyaltyEngineV1.sol`<br>`./src/TLStacks721.sol` |
| **Confidence threshold (1-100)** | 75 |
| **Passes** | 3 |
| **Memory** | 0 records before this scan · 48 after · `6e39654` |

---

## Findings

[90] **1. Drop type zero raises the live supply.**

`TLStacks1155.configureDrop` · Confidence: 90 · seen in 3/3 runs · NEW

**Description**
The drop admin sets dropType to zero and calls configureDrop again, so buyers mint more tokens and the round stays the same.

**Fix**

**Fix (Option A — validate)**:

```diff
+        if (drop.dropType != DropType.REGULAR && drop.dropType != DropType.VELOCITY) revert InvalidDropType();
```

**Fix (Option B — allow-and-handle)**:

```diff
+        if (drop.dropType == DropType.NOT_CONFIGURED) revert InvalidDropType();
+        if (mDrop.payoutReceiver != address(0)) _rounds[nftAddress] += 1;
```

---

[90] **2. Drop type zero replaces a live drop.**

`TLStacks721.configureDrop` · Confidence: 90 · seen in 3/3 runs · NEW

**Description**
The drop admin sets dropType to zero and calls configureDrop again, so the buyer pays for a new token URI or a larger supply.

**Fix**

**Fix (Option A — validate)**:

```diff
+        if (drop.dropType != DropType.REGULAR && drop.dropType != DropType.VELOCITY) revert InvalidDropType();
```

**Fix (Option B — allow-and-handle)**:

```diff
+        if (drop.dropType == DropType.NOT_CONFIGURED) revert InvalidDropType();
+        if (mDrop.payoutReceiver != address(0)) _rounds[nftAddress] += 1;
```

---

[85] **3. buyNow does not pin the listing id.**

`TLAuctionHouse.buyNow` · Confidence: 85 · seen in 3/3 runs · NEW

**Description**
The seller delists the token, takes the assets out, and lists it again, so buyNow still takes the buyer's payment.

**Fix**

```diff
+    function buyNow(address nftAddress, uint256 tokenId, address recipient, address currencyAddress, uint256 maxPrice, uint256 expectedListingId)
+        if (listing.id != expectedListingId) revert ListingChanged();
```

---

[85] **4. The owner pauses settlement and the auction unwinds.**

`TLAuctionHouse.settleAuction` · Confidence: 85 · seen in 2/3 runs · NEW

**Description**
The owner pauses settlement through the grace period, so the seller or the bidder cancels the finished auction.

**Fix**

```diff
-    function settleAuction(address nftAddress, uint256 tokenId) external whenNotPaused nonReentrant {
+    function settleAuction(address nftAddress, uint256 tokenId) external nonReentrant {
```

---

[85] **5. One purchase mints past the velocity end.**

`TLStacks1155._updateDropState` · Confidence: 85 · seen in 2/3 runs · NEW

**Description**
A buyer mints many tokens of one id in one call, so the negative decay rate does not end the sale.

**Fix**

```diff
+        if (drop.decayRate < 0) {
+            uint256 perToken = uint256(-1 * drop.decayRate);
+            uint256 maxMint = perToken == 0 ? drop.supply : (drop.publicDuration + perToken - 1) / perToken;
+            if (numberToMint > maxMint) revert CannotMintMoreThanAllowed();
+        }
```

---

[85] **6. One purchase mints past the velocity end.**

`TLStacks721._updateDropState` · Confidence: 85 · seen in 2/3 runs · NEW

**Description**
A buyer mints many tokens in one call, so the negative decay rate does not end the sale between those tokens.

**Fix**

```diff
+        if (drop.decayRate < 0) {
+            uint256 perToken = uint256(-1 * drop.decayRate);
+            uint256 maxMint = perToken == 0 ? drop.supply : (drop.publicDuration + perToken - 1) / perToken;
+            if (numberToMint > maxMint) revert CannotMintMoreThanAllowed();
+        }
```

---

[80] **7. A zero royalty address keeps the budget.**

`TLAuctionHouse._payoutRoyalties` · Confidence: 80 · seen in 2/3 runs · NEW

**Description**
The royalty loop skips a zero address and keeps its budget, so the next recipient takes that share from the seller.

**Fix**

```diff
-                if (recipients[i] == address(0)) continue;
+                if (recipients[i] == address(0)) {
+                    uint256 skipped = amounts[i] > royaltyBudget ? royaltyBudget : amounts[i];
+                    royaltyBudget -= skipped;
+                    if (royaltyBudget == 0) break;
+                    continue;
+                }
```

---

[80] **8. The payout receiver buys and is repaid.**

`TLAuctionHouse._settleUp` · Confidence: 80 · seen in 2/3 runs · NEW

**Description**
The payout receiver buys the token, and the house returns the price, so the seller gets nothing.

**Fix**

```diff
-        address payoutReceiver,
+        address payoutReceiver,
+        address payer,
         uint256 value
     ) private {
-        _payout(payoutReceiver, currencyAddress, remainingValue);
+        _payout(payoutReceiver == payer ? seller : payoutReceiver, currencyAddress, remainingValue);
```

---

[80] **9. A bid locks funds after the token leaves.**

`TLAuctionHouse.bid` · Confidence: 80 · seen in 1/3 runs · NEW

**Description**
A collection admin moves the token out of the house, so a later bid stays locked until the grace period ends.

**Fix**

```diff
+        if (IERC721(nftAddress).ownerOf(tokenId) != address(this)) revert InvalidListingType();
```

---

[80] **10. A sanction locks the other party's escrow.**

`TLAuctionHouse.cancelUnsettledAuction` · Confidence: 80 · seen in 1/3 runs · NEW

**Description**
A sanctioned seller blocks settlement, so the bidder waits until the auction end plus seven days to recover the bid.

**Fix**

```diff
+        if (_isSanctioned(listing.seller) || _isSanctioned(listing.highestBidder)) {
+            // the unsanctioned party may cancel now
+        } else if (block.timestamp <= listing.startTime + listing.duration + SETTLEMENT_GRACE_PERIOD) {
+            revert SettlementGracePeriodNotOver();
+        }
```

---

[80] **11. The seller cancels a finished auction.**

`TLAuctionHouse.cancelUnsettledAuction` · Confidence: 80 · seen in 3/3 runs · NEW

**Description**
The seller calls cancelUnsettledAuction after seven days, so the bidder gets a refund and does not receive the NFT.

**Fix**

```diff
+        if (_canSettle(nftAddress, tokenId)) revert SettlementStillPossible();
```

---

[80] **12. The payout receiver mints with no payment.**

`TLStacks1155._settleUp` · Confidence: 80 · seen in 3/3 runs · NEW

**Description**
The token pull returns when the buyer is the payout receiver, so purchase still mints and the sale price stays put.

**Fix**

**Fix (Option A — restrict)**:

```diff
+        if (msg.sender == drop.payoutReceiver) revert InvalidPayoutReceiver();
```

**Fix (Option B — allow-and-handle)**:

```diff
-        _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
+        _safeTransferFromERC20(msg.sender, address(this), drop.currencyAddress, totalSale);
+        _safeTransferERC20(drop.payoutReceiver, drop.currencyAddress, totalSale);
```

---

[80] **13. The payout receiver mints with no payment.**

`TLStacks1155.purchase` · Confidence: 80 · seen in 3/3 runs · NEW

**Description**
The payout receiver calls purchase for any recipient, so that caller takes the tokens and pays no sale price.

**Fix**

**Fix (Option A — restrict)**:

```diff
+        if (msg.sender == drop.payoutReceiver) revert InvalidPayoutReceiver();
```

**Fix (Option B — allow-and-handle)**:

```diff
-        _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
+        _safeTransferFromERC20(msg.sender, address(this), drop.currencyAddress, totalSale);
+        _safeTransferERC20(drop.payoutReceiver, drop.currencyAddress, totalSale);
```

---

[80] **14. The payout receiver mints with no payment.**

`TLStacks721._settleUp` · Confidence: 80 · seen in 3/3 runs · NEW

**Description**
The token pull returns when the buyer is the payout receiver, so purchase still mints and the sale price stays put.

**Fix**

**Fix (Option A — restrict)**:

```diff
+        if (msg.sender == drop.payoutReceiver) revert InvalidPayoutReceiver();
```

**Fix (Option B — allow-and-handle)**:

```diff
-        _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
+        _safeTransferFromERC20(msg.sender, address(this), drop.currencyAddress, totalSale);
+        _safeTransferERC20(drop.payoutReceiver, drop.currencyAddress, totalSale);
```

---

[80] **15. The payout receiver mints with no payment.**

`TLStacks721.purchase` · Confidence: 80 · seen in 3/3 runs · NEW

**Description**
The payout receiver calls purchase for any recipient, so that caller takes the NFTs and pays no sale price.

**Fix**

**Fix (Option A — restrict)**:

```diff
+        if (msg.sender == drop.payoutReceiver) revert InvalidPayoutReceiver();
```

**Fix (Option B — allow-and-handle)**:

```diff
-        _safeTransferFromERC20(msg.sender, drop.payoutReceiver, drop.currencyAddress, totalSale);
+        _safeTransferFromERC20(msg.sender, address(this), drop.currencyAddress, totalSale);
+        _safeTransferERC20(drop.payoutReceiver, drop.currencyAddress, totalSale);
```

---

[75] **16. A zero address uses a royalty slot.**

`TLAuctionHouse._payoutRoyalties` · Confidence: 75 · seen in 1/3 runs · NEW

**Description**
The royalty loop counts a zero address in the ten-recipient limit, so a later recipient receives nothing.

**Fix**

```diff
-            if (i == MAX_ROYALTY_RECIPIENTS) break;
+            if (recipients[i] == address(0)) continue;
+            if (paidRecipients == MAX_ROYALTY_RECIPIENTS) break;
```

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [90] | Drop type zero raises the live supply. |
| 2 | [90] | Drop type zero replaces a live drop. |
| 3 | [85] | buyNow does not pin the listing id. |
| 4 | [85] | The owner pauses settlement and the auction unwinds. |
| 5 | [85] | One purchase mints past the velocity end. |
| 6 | [85] | One purchase mints past the velocity end. |
| 7 | [80] | A zero royalty address keeps the budget. |
| 8 | [80] | The payout receiver buys and is repaid. |
| 9 | [80] | A bid locks funds after the token leaves. |
| 10 | [80] | A sanction locks the other party's escrow. |
| 11 | [80] | The seller cancels a finished auction. |
| 12 | [80] | The payout receiver mints with no payment. |
| 13 | [80] | The payout receiver mints with no payment. |
| 14 | [80] | The payout receiver mints with no payment. |
| 15 | [80] | The payout receiver mints with no payment. |
| 16 | [75] | A zero address uses a royalty slot. |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives — they are high-signal leads for manual review. Not scored._

- **getCreator returns the current owner.** — `CreatorLookup.getCreator` · seen in 3/3 runs · NEW — getCreator ignores tokenId and returns Ownable.owner(). getCreator returns the current collection owner, so a sale by that owner pays no royalty.
- **A failed engine returns no royalty.** — `RoyaltyLookup.getRoyalty` · seen in 3/3 runs · NEW — A set engine that reverts returns empty lists and does not call ERC-2981. RoyaltyLookup returns no royalties when the royalty engine reverts, and it does not call the token.
- **The oracle revert blocks the sale.** — `SanctionsCompliance._isSanctioned` · seen in 3/3 runs · NEW — The oracle call has no gas cap and no catch. A revert in the sanctions oracle makes bid, settle, and purchase revert.
- **The owner change skips the royalty.** — `TLAuctionHouse._isPrimarySale` · seen in 3/3 runs · NEW — _isPrimarySale reads the current collection owner at settlement. The collection owner assigns ownership to the seller after a bid, so the royalty recipient gets nothing.
- **The outbound token send does not check the balance.** — `TLAuctionHouse._payout` · seen in 1/3 runs · NEW — The bid pull reverts unless the house balance rises by the full amount. The payout treats a true return as a full send. This trace did not run a fee-on-transfer token.
- **A failed royalty send can stick.** — `TLAuctionHouse._payout` · seen in 2/3 runs · NEW — A failed ETH send credits claimableFunds for that recipient. claimFunds pays only the recipient. A contract with no withdraw path cannot take the credit.
- **The royalty lookup stops at the gas cap.** — `TLAuctionHouse._payoutRoyalties` · seen in 3/3 runs · NEW — Settlement calls getRoyalty with a 1e6 gas cap and the catch pays nothing. The royalty lookup stops at one million gas, so the seller keeps the royalty share.
- **A failed royalty lookup pays the seller.** — `TLAuctionHouse._payoutRoyalties` · seen in 3/3 runs · NEW — The catch after getRoyalty pays no royalty and the sale still completes. A failed royalty lookup pays no royalty, so the seller keeps that share of the bid.
- **The owner raises the fee after a bid.** — `TLAuctionHouse._settleUp` · seen in 3/3 runs · NEW — protocolFeeBps is read at settlement and is not stored on the listing. The owner raises the protocol fee after a bid, so the seller receives less of the escrowed price.
- **The admin raises the royalty after a bid.** — `TLAuctionHouse._settleUp` · seen in 3/3 runs · NEW — Royalties are read at settlement, and delist reverts after the first bid. The collection admin raises the royalty after a bid, so the seller receives less of the escrowed price.
- **Bids can extend the auction past the duration cap.** — `TLAuctionHouse.bid` · seen in 1/3 runs · NEW — list rejects a duration above 30 days. bid adds five minutes with no cap on the total. The seller can settle five minutes after the last bid.
- **The oracle revert blocks claimFunds.** — `TLAuctionHouse.claimFunds` · seen in 3/3 runs · NEW — claimFunds calls the sanctions oracle with no gas cap and no catch. A revert in the sanctions oracle makes claimFunds revert, so the bidder cannot take the escrowed funds.
- **claimNft leaves the NFT in the house.** — `TLAuctionHouse.claimNft` · seen in 3/3 runs · NEW — claimNft calls transferFrom with the house as the caller. The collection admin blocks the house in the transfer validator, so the seller cannot take the NFT back.
- **delist has no claim path.** — `TLAuctionHouse.delist` · seen in 3/3 runs · NEW — delist sends the NFT only to the seller and reverts if that transfer fails. A seller with no bid has no claim path if the return transfer fails. This trace did not find that transfer.
- **getNextBid returns 1 before the first bid.** — `TLAuctionHouse.getNextBid` · seen in 3/3 runs · NEW — getNextBid calls _calcNextBid on a zero highest bid. getNextBid returns 1 when no bid exists, but bid rejects any amount under the reserve price.
- **The royalty view and the settlement use different gas caps.** — `TLAuctionHouse.getRoyalty` · seen in 1/3 runs · NEW — getRoyalty calls the helper with no gas cap. Settlement stops the lookup at 1000000 gas and pays no royalty on failure. This trace did not measure a lookup that crosses that cap.
- **getRoyalty returns the raw royalty amounts.** — `TLAuctionHouse.getRoyalty` · seen in 3/3 runs · NEW — getRoyalty returns the helper arrays with no 10 percent cap. getRoyalty returns the full royalty, but settleAuction pays at most 10 percent of the price.
- **The fee setter stores the zero address.** — `TLStacks1155._setProtocolFeeSettings` · seen in 2/3 runs · NEW — The helper writes the receiver with no zero-address check. A later purchase sends the fee to that address.
- **A lower price rejects the pending purchase.** — `TLStacks1155._settleUp` · seen in 1/3 runs · NEW — _settleUp requires msg.value to equal the cost. A drop admin who lowers the price by one wei makes a pending purchase revert.
- **The purchase pays a sanctioned fee receiver.** — `TLStacks1155._settleUp` · seen in 3/3 runs · NEW — purchase checks the buyer, the recipient, and the payout receiver, not the fee receiver. A purchase sends the protocol fee to a fee receiver the oracle has marked.
- **closeDrop skips the pause check.** — `TLStacks1155.closeDrop` · seen in 2/3 runs · NEW — closeDrop checks only the drop admin. The other drop writes also check pause. A drop admin can close the drop while the sale is paused.
- **Any payer can mint to an allowlisted wallet.** — `TLStacks1155.purchase` · seen in 2/3 runs · NEW — The Merkle leaf binds the recipient, not the payer. Any payer can use up that wallet's allowance.
- **Presale mints use the public allowance.** — `TLStacks1155.purchase` · seen in 2/3 runs · NEW — Presale and public sale share one _numberMinted counter for the recipient. A presale mint lowers the public allowance for that recipient.
- **The fee receiver can be the zero address.** — `TLStacks1155.setProtocolFeeSettings` · seen in 2/3 runs · NEW — The setter stores any receiver. The auction house rejects the zero address. The owner sets the fee receiver to the zero address, so the next purchase sends the fee there.
- **The fee setter stores the zero address.** — `TLStacks721._setProtocolFeeSettings` · seen in 3/3 runs · NEW — _setProtocolFeeSettings writes the receiver with no zero-address check. The owner sets the fee receiver to the zero address, so _settleUp sends the fee there.
- **A lower price rejects the pending purchase.** — `TLStacks721._settleUp` · seen in 1/3 runs · NEW — _settleUp requires msg.value to equal the cost. A drop admin who lowers the price by one wei makes a pending purchase revert.
- **The purchase pays a sanctioned fee receiver.** — `TLStacks721._settleUp` · seen in 3/3 runs · NEW — purchase checks the buyer, the recipient, and the payout receiver, not the fee receiver. A purchase sends the protocol fee to a fee receiver the oracle has marked.
- **closeDrop skips the pause check.** — `TLStacks721.closeDrop` · seen in 3/3 runs · NEW — closeDrop checks only the drop admin. The other drop writes also check pause and sanctions. A sanctioned drop admin can close the drop while the sale is paused. No stolen funds were shown.
- **Any payer can mint to an allowlisted wallet.** — `TLStacks721.purchase` · seen in 3/3 runs · NEW — The allowance and the Merkle leaf bind the recipient, not the payer. Any payer can mint to an allowlisted wallet, so the payer can use up that wallet's allowance.
- **Presale mints use the public allowance.** — `TLStacks721.purchase` · seen in 3/3 runs · NEW — Presale and public sale share one _numberMinted counter for the recipient. A recipient who mints in the presale keeps that count, so the public cap can already be spent.
- **The fee receiver can be the zero address.** — `TLStacks721.setProtocolFeeSettings` · seen in 3/3 runs · NEW — The stacks setter stores any receiver. The auction house rejects the zero address. The owner sets the fee receiver to the zero address, so the next purchase sends the fee there.
- **A self transfer skips the token pull.** — `TransferHelper._safeTransferFromERC20` · seen in 3/3 runs · NEW — The helper returns when the sender and the recipient are the same address. The helper skips the pull when the payer is the receiver, and the mint in purchase still runs.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)

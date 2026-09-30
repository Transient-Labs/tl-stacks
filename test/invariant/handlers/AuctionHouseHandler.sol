// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin-contracts-5.6.1/utils/math/Math.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {CreatorLookup} from "src/helpers/CreatorLookup.sol";
import {ListingType, Listing, ListingConfig} from "src/utils/TLAuctionHouseUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {BlocklistERC20} from "test/utils/BlocklistERC20.sol";
import {RevertingReceiver} from "test/utils/Receiver.sol";
import {MockSanctionsOracle} from "test/utils/MockSanctionsOracle.sol";
import {MockRoyaltyLookup} from "test/utils/MockRoyaltyLookup.sol";

/// @dev Drives TLAuctionHouse through arbitrary interleavings of seller, bidder, owner, and oracle actions
/// @dev Every call into the auction house is wrapped in try/catch so the handler itself never reverts, which lets
///      the suite run with `fail_on_revert = true` and surface any accidental revert in the harness. Properties that
///      must hold after a successful call are recorded as violations (with a reason) and checked by
///      `invariant_handlerAssertions`.
contract AuctionHouseHandler is Test {
    uint256 public constant NUM_TOKENS = 12;
    uint256 internal constant BASIS = 10_000;

    // token states `_pickToken` can aim for
    uint256 internal constant STATE_UNESCROWED = 0;
    uint256 internal constant STATE_LISTED = 1;
    uint256 internal constant STATE_BID = 2;
    uint256 internal constant STATE_CLAIMABLE = 3;

    TLAuctionHouse public ah;
    ERC721TL public nft;
    MockERC20 public coin;
    BlocklistERC20 public bcoin;
    MockSanctionsOracle public oracle;
    MockRoyaltyLookup public royaltyLookup;
    CreatorLookup public creatorLookup;

    address[] public actors; // 4 EOAs + 1 contract that rejects ETH
    address[] public feeReceivers; // EOA + contract that rejects ETH
    address payable[] public royaltyRecipients; // 2 EOAs + contract that rejects ETH, disjoint from actors
    address[] public creditHolders; // every address that can ever be credited
    address[] public currencies; // ETH, standard ERC-20, blocklist ERC-20

    // ghost state
    uint256 public ghostMaxListingId;
    mapping(uint256 tokenId => bool) public ghostZeroFee; // I-6: fee waiver on the live listing
    uint256 public violations;
    string public lastViolation;

    mapping(string => uint256) public successes;

    struct SaleSnap {
        address feeReceiver;
        uint256 bps;
        bool primary;
        uint256 fee;
        uint256 payout;
        uint256[] royalty;
    }

    constructor() {
        oracle = new MockSanctionsOracle();
        ah = new TLAuctionHouse(address(this), address(oracle));
        creatorLookup = new CreatorLookup();
        royaltyLookup = new MockRoyaltyLookup();
        ah.setCreatorLookup(address(creatorLookup));
        ah.setRoyaltyLookup(address(royaltyLookup));

        feeReceivers.push(makeAddr("feeReceiver"));
        feeReceivers.push(address(new RevertingReceiver()));
        ah.setProtocolFeeSettings(feeReceivers[0], 250);

        royaltyRecipients.push(payable(makeAddr("royalty0")));
        royaltyRecipients.push(payable(makeAddr("royalty1")));
        royaltyRecipients.push(payable(address(new RevertingReceiver())));

        actors.push(makeAddr("creator"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(address(new RevertingReceiver()));

        coin = new MockERC20(address(this));
        bcoin = new BlocklistERC20(address(this));
        bcoin.setBlocked(actors[4], true);
        bcoin.setBlocked(feeReceivers[1], true);
        bcoin.setBlocked(royaltyRecipients[2], true);
        ah.setCurrencyAllowed(address(coin), true);
        ah.setCurrencyAllowed(address(bcoin), true);
        currencies.push(address(0));
        currencies.push(address(coin));
        currencies.push(address(bcoin));

        address[] memory empty = new address[](0);
        nft = new ERC721TL(false);
        nft.initialize("Invariant", "INV", actors[0], 1_000, actors[0], empty, false, address(0), 0, address(0));
        vm.startPrank(actors[0]);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            nft.mint(actors[i % actors.length], "https://arweave.net/invariant");
        }
        vm.stopPrank();

        for (uint256 i = 0; i < actors.length; ++i) {
            vm.startPrank(actors[i]);
            nft.setApprovalForAll(address(ah), true);
            coin.approve(address(ah), type(uint256).max);
            bcoin.approve(address(ah), type(uint256).max);
            vm.stopPrank();
            creditHolders.push(actors[i]);
        }
        for (uint256 i = 0; i < feeReceivers.length; ++i) {
            creditHolders.push(feeReceivers[i]);
        }
        for (uint256 i = 0; i < royaltyRecipients.length; ++i) {
            creditHolders.push(royaltyRecipients[i]);
        }

        _setRoyaltySchedule(1);
    }

    /////////////////////////////////////////////////////////////////////
    // SELLER ACTIONS
    /////////////////////////////////////////////////////////////////////

    function list(
        uint256 tokenSeed,
        uint256 typeSeed,
        uint256 currencySeed,
        uint256 payoutSeed,
        uint256 recipientSeed,
        uint256 openSeed,
        uint256 reservePrice,
        uint256 buyNowPrice,
        uint256 duration
    ) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_UNESCROWED);
        address seller = _sellerFor(tokenId, payoutSeed);
        ListingConfig memory cfg = _config(
            tokenId,
            ListingType(_bound(typeSeed, 0, 5)),
            _currency(currencySeed),
            payoutSeed,
            recipientSeed,
            openSeed,
            reservePrice,
            buyNowPrice,
            duration
        );

        vm.prank(seller);
        try ah.list(cfg) {
            _hit("list");
            _afterList(tokenId, seller, cfg);
        } catch {}
    }

    function batchList(
        uint256 tokenSeed,
        uint256 typeSeed,
        uint256 currencySeed,
        uint256 payoutSeed,
        uint256 openSeed,
        uint256 reservePrice,
        uint256 buyNowPrice,
        uint256 duration
    ) external {
        uint256 first = _pickToken(tokenSeed, STATE_UNESCROWED);
        address seller = _sellerFor(first, payoutSeed);
        uint256 second;
        for (uint256 i = 1; i < NUM_TOKENS; ++i) {
            uint256 candidate = _tokenId(tokenSeed % NUM_TOKENS + i);
            if (nft.ownerOf(candidate) == seller) {
                second = candidate;
                break;
            }
        }
        if (second == 0) return;

        // private sales need a recipient, so batch the other types only
        ListingType type_ = ListingType(_bound(typeSeed, 0, 4));
        ListingConfig[] memory cfgs = new ListingConfig[](2);
        cfgs[0] = _config(
            first, type_, _currency(currencySeed), payoutSeed, 0, openSeed, reservePrice, buyNowPrice, duration
        );
        cfgs[1] = _config(
            second, type_, _currency(currencySeed), payoutSeed, 0, openSeed, reservePrice, buyNowPrice, duration
        );

        vm.prank(seller);
        try ah.batchList(cfgs) {
            _hit("batchList");
            _afterList(first, seller, cfgs[0]);
            _afterList(second, seller, cfgs[1]);
        } catch {}
    }

    function updateListing(
        uint256 tokenSeed,
        uint256 payoutSeed,
        uint256 recipientSeed,
        uint256 openSeed,
        uint256 reservePrice,
        uint256 buyNowPrice,
        uint256 duration
    ) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        if (prev.seller == address(0)) return;
        ListingConfig memory cfg = _config(
            tokenId,
            prev.type_,
            prev.currencyAddress,
            payoutSeed,
            recipientSeed,
            openSeed,
            reservePrice,
            buyNowPrice,
            duration
        );

        vm.prank(prev.seller);
        try ah.updateListing(cfg) {
            _hit("updateListing");
            Listing memory l = ah.getListing(address(nft), tokenId);
            _check(prev.highestBidder == address(0), "G-2: listing updated after a bid");
            _check(l.seller == prev.seller, "updateListing: seller changed");
            _check(l.zeroProtocolFee == ghostZeroFee[tokenId], "I-6: fee waiver not carried through update");
            _check(
                l.type_ != ListingType.RESERVE_AUCTION_PLUS_BUY_NOW || l.buyNowPrice > l.reservePrice,
                "updateListing: buy now not above reserve"
            );
            _checkNewId(l.id);
        } catch {}
    }

    function updatePayoutReceiver(uint256 tokenSeed, uint256 payoutSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        address newPayoutReceiver = _actor(payoutSeed);

        vm.prank(prev.seller);
        try ah.updatePayoutReceiver(address(nft), tokenId, newPayoutReceiver) {
            _hit("updatePayoutReceiver");
            Listing memory l = ah.getListing(address(nft), tokenId);
            _check(l.payoutReceiver == newPayoutReceiver, "updatePayoutReceiver: not stored");
            _check(l.id == prev.id, "updatePayoutReceiver: id changed");
            _check(
                l.highestBid == prev.highestBid && l.highestBidder == prev.highestBidder,
                "updatePayoutReceiver: bid changed"
            );
        } catch {}
    }

    function delist(uint256 tokenSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        Listing memory prev = ah.getListing(address(nft), tokenId);

        vm.prank(prev.seller);
        try ah.delist(address(nft), tokenId) {
            _hit("delist");
            _check(prev.highestBidder == address(0), "G-7: delisted with a bid");
            _check(nft.ownerOf(tokenId) == prev.seller, "delist: nft not returned");
            ghostZeroFee[tokenId] = false;
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // BUYER ACTIONS
    /////////////////////////////////////////////////////////////////////

    function bid(uint256 tokenSeed, uint256 bidderSeed, uint256 amountSeed, uint256 lowballSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        address bidder = _actor(bidderSeed);
        address currency = prev.currencyAddress;

        uint256 next = ah.getNextBid(address(nft), tokenId);
        uint256 amount = lowballSeed % 8 == 0 ? _bound(amountSeed, 0, next - 1) : _bound(amountSeed, next, next * 3);
        _fund(bidder, currency, amount);

        uint256 prevBidderOwed = prev.highestBidder == address(0) ? 0 : _owed(prev.highestBidder, currency);
        uint256 bidderOwed = _owed(bidder, currency);
        bool reserveFirstBid = prev.highestBidder == address(0)
            && (prev.type_ == ListingType.RESERVE_AUCTION || prev.type_ == ListingType.RESERVE_AUCTION_PLUS_BUY_NOW);
        uint256 effectiveEnd = reserveFirstBid ? block.timestamp + prev.duration : prev.startTime + prev.duration;

        vm.prank(bidder);
        try ah.bid{value: currency == address(0) ? amount : 0}(address(nft), tokenId, currency, amount, prev.id) {
            _hit("bid");
            Listing memory l = ah.getListing(address(nft), tokenId);
            _check(
                l.highestBidder == bidder && l.recipient == bidder && l.highestBid == amount, "bid: state not stored"
            );
            _check(l.id == prev.id, "bid: id changed");
            _check(block.timestamp >= prev.openTime, "G-11: bid before open time");
            _check(block.timestamp <= effectiveEnd, "G-13/G-14: bid after auction end");
            if (prev.highestBidder == address(0)) {
                _check(amount >= Math.max(prev.reservePrice, 1), "G-12: first bid below reserve");
            } else {
                uint256 minBid = prev.highestBid + Math.mulDiv(prev.highestBid, 500, BASIS, Math.Rounding.Ceil);
                _check(amount >= minBid, "G-15: outbid below 5% step");
                if (prev.highestBidder == bidder) {
                    _check(
                        _owed(bidder, currency) + amount == bidderOwed + prev.highestBid,
                        "bid: self-outbid refund mismatch"
                    );
                } else {
                    _check(
                        _owed(prev.highestBidder, currency) == prevBidderOwed + prev.highestBid,
                        "bid: previous bidder not made whole"
                    );
                }
            }
            uint256 remaining = effectiveEnd > block.timestamp ? effectiveEnd - block.timestamp : 0;
            uint256 expectedEnd = remaining < ah.EXTENSION_TIME() ? block.timestamp + ah.EXTENSION_TIME() : effectiveEnd;
            _check(l.startTime + l.duration == expectedEnd, "bid: anti-snipe extension mismatch");
        } catch {}
    }

    function topUpBid(uint256 tokenSeed, uint256 callerSeed, uint256 amountSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_BID);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        address caller =
            prev.highestBidder != address(0) && callerSeed % 4 != 0 ? prev.highestBidder : _actor(callerSeed);
        uint256 amount = _bound(amountSeed, 0, 10 ether);
        _fund(caller, prev.currencyAddress, amount);

        vm.prank(caller);
        try ah.topUpBid{value: prev.currencyAddress == address(0) ? amount : 0}(
            address(nft), tokenId, amount, prev.id
        ) {
            _hit("topUpBid");
            Listing memory l = ah.getListing(address(nft), tokenId);
            _check(caller == prev.highestBidder, "G-18: top up by non-highest bidder");
            _check(amount > 0, "topUpBid: zero top up accepted");
            _check(block.timestamp <= prev.startTime + prev.duration, "G-19: top up after end");
            _check(l.highestBid == prev.highestBid + amount, "topUpBid: bid not raised by amount");
            _check(l.startTime == prev.startTime && l.duration == prev.duration, "I-10: top up moved the end");
        } catch {}
    }

    function buyNow(uint256 tokenSeed, uint256 buyerSeed, uint256 recipientSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        address buyer = _actor(buyerSeed);
        address recipient =
            prev.type_ == ListingType.PRIVATE_SALE && recipientSeed % 4 != 0 ? prev.recipient : _actor(recipientSeed);
        uint256 price = prev.buyNowPrice;
        _fund(buyer, prev.currencyAddress, price);
        SaleSnap memory snap = _snapSale(prev);

        vm.prank(buyer);
        try ah.buyNow{value: prev.currencyAddress == address(0) ? price : 0}(
            address(nft), tokenId, recipient, prev.currencyAddress, price, prev.id
        ) {
            _hit("buyNow");
            _check(prev.highestBidder == address(0), "G-34: buy now after a bid");
            _check(block.timestamp >= prev.openTime, "G-35: buy before open time");
            _check(
                prev.type_ != ListingType.PRIVATE_SALE || recipient == prev.recipient, "G-30: private sale recipient"
            );
            _check(nft.ownerOf(tokenId) == recipient, "buyNow: nft not delivered");
            _checkSale(prev, snap, price, buyer);
            ghostZeroFee[tokenId] = false;
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // SETTLEMENT & CLAIMS
    /////////////////////////////////////////////////////////////////////

    function settleAuction(uint256 tokenSeed, uint256 callerSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_BID);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        SaleSnap memory snap = _snapSale(prev);

        vm.prank(_actor(callerSeed));
        try ah.settleAuction(address(nft), tokenId) {
            _hit("settleAuction");
            _check(prev.highestBidder != address(0), "G-21: settled without a bid");
            _check(block.timestamp > prev.startTime + prev.duration, "I-8: settled before end");
            _check(nft.ownerOf(tokenId) == prev.highestBidder, "settle: nft not delivered");
            _check(
                ah.getListing(address(nft), tokenId).type_ == ListingType.NOT_CONFIGURED, "settle: listing not deleted"
            );
            _checkSale(prev, snap, prev.highestBid, address(0));
            ghostZeroFee[tokenId] = false;
        } catch {}
    }

    function cancelUnsettledAuction(uint256 tokenSeed, uint256 callerSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_BID);
        Listing memory prev = ah.getListing(address(nft), tokenId);
        address caller =
            callerSeed % 3 == 0 ? prev.seller : callerSeed % 3 == 1 ? prev.highestBidder : _actor(callerSeed);
        uint256 bidderCredit =
            prev.highestBidder == address(0) ? 0 : ah.claimableFunds(prev.highestBidder, prev.currencyAddress);

        vm.prank(caller);
        try ah.cancelUnsettledAuction(address(nft), tokenId) {
            _hit("cancelUnsettledAuction");
            _check(caller == prev.seller || caller == prev.highestBidder, "G-27: cancel by third party");
            _check(
                block.timestamp > prev.startTime + prev.duration + ah.SETTLEMENT_GRACE_PERIOD(),
                "I-8: canceled before grace period"
            );
            _check(
                ah.claimableFunds(prev.highestBidder, prev.currencyAddress) == bidderCredit + prev.highestBid,
                "cancel: bid not credited"
            );
            _check(ah.claimableNft(address(nft), tokenId) == prev.seller, "cancel: nft not held for seller");
            _check(nft.ownerOf(tokenId) == address(ah), "cancel: nft left escrow");
            ghostZeroFee[tokenId] = false;
        } catch {}
    }

    function claimFunds(uint256 holderSeed, uint256 currencySeed, uint256 toSeed) external {
        address currency = _currency(currencySeed);
        address holder = creditHolders[holderSeed % creditHolders.length];
        if (holderSeed % 8 != 0) {
            for (uint256 i = 0; i < creditHolders.length; ++i) {
                address candidate = creditHolders[(holderSeed % creditHolders.length + i) % creditHolders.length];
                if (ah.claimableFunds(candidate, currency) > 0) {
                    holder = candidate;
                    break;
                }
            }
        }
        address to = _actor(toSeed);
        uint256 credit = ah.claimableFunds(holder, currency);
        uint256 toBalance = _balance(to, currency);

        vm.prank(holder);
        try ah.claimFunds(currency, to) {
            _hit("claimFunds");
            _check(credit > 0, "G-36: claimed zero credit");
            _check(ah.claimableFunds(holder, currency) == 0, "I-11: credit not cleared");
            _check(_balance(to, currency) == toBalance + credit, "I-11: claim paid a different amount");
        } catch {}
    }

    function claimNft(uint256 tokenSeed, uint256 claimantSeed, uint256 toSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_CLAIMABLE);
        address claimant = ah.claimableNft(address(nft), tokenId);
        if (claimant == address(0) || claimantSeed % 4 == 0) claimant = _actor(claimantSeed);
        address to = _actor(toSeed);
        address stored = ah.claimableNft(address(nft), tokenId);

        vm.prank(claimant);
        try ah.claimNft(address(nft), tokenId, to) {
            _hit("claimNft");
            _check(stored == claimant, "G-37: nft claimed by the wrong account");
            _check(nft.ownerOf(tokenId) == to, "claimNft: nft not delivered");
            _check(ah.claimableNft(address(nft), tokenId) == address(0), "claimNft: claim not cleared");
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // TIME, OWNER, ORACLE, COLLECTION
    /////////////////////////////////////////////////////////////////////

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + _bound(secondsSeed, 0, 8 days));
        _hit("warp");
    }

    function setProtocolFeeSettings(uint256 receiverSeed, uint256 bps) external {
        bps = _bound(bps, 0, 600);
        bool ok;
        try ah.setProtocolFeeSettings(feeReceivers[receiverSeed % feeReceivers.length], bps) {
            ok = true;
            _hit("setProtocolFeeSettings");
        } catch {}
        _check(ok == (bps <= ah.MAX_PROTOCOL_FEE_BPS()), "G-38: protocol fee cap not enforced");
    }

    function removeProtocolFee(uint256 tokenSeed) external {
        uint256 tokenId = _pickToken(tokenSeed, STATE_LISTED);
        try ah.removeProtocolFee(address(nft), tokenId) {
            _hit("removeProtocolFee");
            ghostZeroFee[tokenId] = true;
        } catch {}
    }

    function setPaused(uint256 seed) external {
        try ah.pause(seed % 8 == 0) {
            _hit("setPaused");
        } catch {}
    }

    function setCurrencyAllowed(uint256 currencySeed, bool allowed) external {
        ah.setCurrencyAllowed(currencySeed % 2 == 0 ? address(coin) : address(bcoin), allowed);
        _hit("setCurrencyAllowed");
    }

    function setRoyaltySchedule(uint256 mode) external {
        _setRoyaltySchedule(mode % 7);
        _hit("setRoyaltySchedule");
    }

    function setSanctioned(uint256 actorSeed, uint256 statusSeed) external {
        oracle.setSanctioned(_actor(actorSeed), statusSeed % 8 == 0);
        _hit("setSanctioned");
    }

    /// @dev Moves the collection owner, which flips which sellers are treated as the creator (X-1)
    function transferCollectionOwnership(uint256 newOwnerSeed) external {
        vm.prank(nft.owner());
        try nft.transferOwnership(_actor(newOwnerSeed)) {
            _hit("transferCollectionOwnership");
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // VIEWS FOR THE INVARIANT CONTRACT
    /////////////////////////////////////////////////////////////////////

    function numCreditHolders() external view returns (uint256) {
        return creditHolders.length;
    }

    function numCurrencies() external view returns (uint256) {
        return currencies.length;
    }

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _config(
        uint256 tokenId,
        ListingType type_,
        address currency,
        uint256 payoutSeed,
        uint256 recipientSeed,
        uint256 openSeed,
        uint256 reservePrice,
        uint256 buyNowPrice,
        uint256 duration
    ) internal view returns (ListingConfig memory) {
        return ListingConfig({
            nftAddress: address(nft),
            tokenId: tokenId,
            type_: type_,
            payoutReceiver: _actor(payoutSeed),
            currencyAddress: currency,
            openTime: openSeed % 3 == 0 ? 0 : block.timestamp + _bound(openSeed, 0, 1 days),
            reservePrice: _bound(reservePrice, 0, 50 ether),
            auctionDuration: _bound(duration, 0, 31 days),
            buyNowPrice: _bound(buyNowPrice, 0, 100 ether),
            recipient: _actor(recipientSeed)
        });
    }

    function _afterList(uint256 tokenId, address seller, ListingConfig memory cfg) internal {
        Listing memory l = ah.getListing(address(nft), tokenId);
        _check(nft.ownerOf(tokenId) == address(ah), "list: nft not escrowed");
        _check(l.seller == seller, "list: seller not stored");
        _check(cfg.type_ != ListingType.NOT_CONFIGURED, "list: unconfigured type accepted");
        _check(cfg.auctionDuration <= ah.MAX_AUCTION_DURATION() || l.duration == 0, "G-43: duration cap bypassed");
        _check(
            l.type_ != ListingType.RESERVE_AUCTION_PLUS_BUY_NOW || l.buyNowPrice > l.reservePrice,
            "list: buy now not above reserve"
        );
        _check(l.openTime == Math.max(cfg.openTime, block.timestamp), "list: open time not clamped");
        _check(!l.zeroProtocolFee, "list: new listing starts fee-waived");
        _checkNewId(l.id);
        ghostZeroFee[tokenId] = false;
    }

    function _checkNewId(uint256 id) internal {
        _check(id > ghostMaxListingId, "listing id did not increase");
        ghostMaxListingId = id;
    }

    function _snapSale(Listing memory l) internal view returns (SaleSnap memory snap) {
        snap.feeReceiver = ah.protocolFeeReceiver();
        snap.bps = ah.protocolFeeBps();
        snap.primary = nft.owner() == l.seller;
        snap.fee = _owed(snap.feeReceiver, l.currencyAddress);
        snap.payout = _owed(l.payoutReceiver, l.currencyAddress);
        snap.royalty = new uint256[](royaltyRecipients.length);
        for (uint256 i = 0; i < royaltyRecipients.length; ++i) {
            snap.royalty[i] = _owed(royaltyRecipients[i], l.currencyAddress);
        }
    }

    /// @dev E-1: fee + royalties + payout remainder == value, each leg within its cap
    /// @param payer The account that paid `value` in this call, or zero if it was escrowed earlier
    function _checkSale(Listing memory l, SaleSnap memory snap, uint256 value, address payer) internal {
        address currency = l.currencyAddress;
        int256 feeDelta = _delta(_owed(snap.feeReceiver, currency), snap.fee);
        int256 royaltyDelta;
        for (uint256 i = 0; i < royaltyRecipients.length; ++i) {
            royaltyDelta += _delta(_owed(royaltyRecipients[i], currency), snap.royalty[i]);
        }
        int256 payoutDelta = _delta(_owed(l.payoutReceiver, currency), snap.payout);
        if (l.payoutReceiver == payer) payoutDelta += int256(value);

        uint256 expectedFee = l.zeroProtocolFee ? 0 : value * snap.bps / BASIS;
        _check(feeDelta == int256(expectedFee), "E-1/I-13: protocol fee mismatch");
        _check(royaltyDelta >= 0 && royaltyDelta <= int256(value * 1_000 / BASIS), "E-1/I-14: royalty cap exceeded");
        if (snap.primary) _check(royaltyDelta == 0, "E-1: royalties paid on a primary sale");
        _check(payoutDelta >= 0, "E-1: payout receiver lost funds");
        _check(feeDelta + royaltyDelta + payoutDelta == int256(value), "E-1: payout legs don't sum to value");
    }

    function _setRoyaltySchedule(uint256 mode) internal {
        royaltyLookup.setShouldRevert(false);
        address payable[] memory r;
        uint256[] memory a;
        if (mode == 0) {
            // no royalties
            r = new address payable[](0);
            a = new uint256[](0);
        } else if (mode == 1) {
            r = new address payable[](1);
            a = new uint256[](1);
            (r[0], a[0]) = (royaltyRecipients[0], 500);
        } else if (mode == 2) {
            // 3% + 4% + 5% exceeds the 10% cap, and the last recipient rejects ETH
            r = new address payable[](3);
            a = new uint256[](3);
            (r[0], a[0]) = (royaltyRecipients[0], 300);
            (r[1], a[1]) = (royaltyRecipients[1], 400);
            (r[2], a[2]) = (royaltyRecipients[2], 500);
        } else if (mode == 3) {
            // zero address and escrow entries are skipped; the huge share is capped
            r = new address payable[](3);
            a = new uint256[](3);
            (r[0], a[0]) = (payable(address(0)), 200);
            (r[1], a[1]) = (payable(address(ah)), 200);
            (r[2], a[2]) = (royaltyRecipients[1], 5_000);
        } else if (mode == 4) {
            // length mismatch is ignored
            r = new address payable[](2);
            a = new uint256[](1);
            (r[0], a[0]) = (royaltyRecipients[0], 500);
            r[1] = royaltyRecipients[1];
        } else if (mode == 5) {
            royaltyLookup.setShouldRevert(true);
        } else {
            // 12 entries, only the first 10 can be paid
            r = new address payable[](12);
            a = new uint256[](12);
            for (uint256 i = 0; i < 12; ++i) {
                (r[i], a[i]) = (royaltyRecipients[i % royaltyRecipients.length], 90);
            }
        }
        royaltyLookup.setSchedule(r, a, true);
    }

    function _fund(address who, address currency, uint256 amount) internal {
        if (currency == address(0)) {
            vm.deal(who, who.balance + amount);
        } else {
            // the handler holds the rest of the supply; a transfer to a blocklisted account just leaves it unfunded
            try IERC20(currency).transfer(who, amount) {} catch {}
        }
    }

    function _balance(address who, address currency) internal view returns (uint256) {
        return currency == address(0) ? who.balance : IERC20(currency).balanceOf(who);
    }

    /// @dev Wallet balance plus claimable credit, so a payout counts whether it was sent or credited
    function _owed(address who, address currency) internal view returns (uint256) {
        return _balance(who, currency) + ah.claimableFunds(who, currency);
    }

    function _delta(uint256 after_, uint256 before_) internal pure returns (int256) {
        return int256(after_) - int256(before_);
    }

    /// @dev Returns a token in `state` when one exists, so actions aren't wasted on tokens that can't succeed. One
    ///      call in eight uses the raw seed instead, so revert paths on tokens in other states are still exercised.
    function _pickToken(uint256 seed, uint256 state) internal view returns (uint256) {
        if (seed % 8 == 0) return _tokenId(seed);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            uint256 tokenId = _tokenId(seed % NUM_TOKENS + i);
            bool match_;
            if (state == STATE_UNESCROWED) {
                match_ = nft.ownerOf(tokenId) != address(ah);
            } else if (state == STATE_LISTED) {
                match_ = ah.getListing(address(nft), tokenId).seller != address(0);
            } else if (state == STATE_BID) {
                match_ = ah.getListing(address(nft), tokenId).highestBidder != address(0);
            } else {
                match_ = ah.claimableNft(address(nft), tokenId) != address(0);
            }
            if (match_) return tokenId;
        }
        return _tokenId(seed);
    }

    /// @dev The token owner, or a random actor when the house holds the token. Pranking the house itself would let
    ///      it "list" its own escrow, which no real caller can do.
    function _sellerFor(uint256 tokenId, uint256 seed) internal view returns (address seller) {
        seller = nft.ownerOf(tokenId);
        if (seller == address(ah)) seller = _actor(seed);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _tokenId(uint256 seed) internal pure returns (uint256) {
        return seed % NUM_TOKENS + 1;
    }

    function _currency(uint256 seed) internal view returns (address) {
        return currencies[seed % currencies.length];
    }

    function _check(bool ok, string memory why) internal {
        if (!ok) {
            violations++;
            lastViolation = why;
        }
    }

    function _hit(string memory name) internal {
        successes[name]++;
    }
}

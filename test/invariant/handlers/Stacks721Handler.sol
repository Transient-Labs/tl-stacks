// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {ERC721TL} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {Drop} from "src/utils/TLStacks721Utils.sol";
import {DropPhase, DropType} from "src/utils/CommonUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {Merkle} from "test/utils/murky/Merkle.sol";

/// @dev Drives TLStacks721 through arbitrary interleavings of drop admin, buyer, and owner actions on two collections
/// @dev Calls into the stacks contract are wrapped in try/catch so the handler never reverts (the suite runs with
///      `fail_on_revert = true`). Per-call properties are recorded as violations and checked by
///      `invariant_handlerAssertions`.
contract Stacks721Handler is Test {
    uint256 internal constant BASIS = 10_000;
    string internal constant BASE_URI = "ipfs://drop";

    TLStacks721 public stacks;
    MockERC20 public coin;
    address[] public nfts;
    address[] public actors; // buyers and recipients
    address[] public payoutReceivers; // disjoint from actors and the fee receiver
    address public admin = makeAddr("dropAdmin");
    address public feeReceiver = makeAddr("feeReceiver");

    bytes32 public presaleRoot;
    uint256[] public presaleAllowances; // per actor, the count in their merkle leaf
    mapping(uint256 actorIndex => bytes32[]) internal _proofs;

    // ghost state
    mapping(address nft => uint256) public ghostRound;
    mapping(address nft => mapping(uint256 round => bool)) public ghostWaived;
    mapping(address nft => uint256) public ghostMinted; // across all rounds
    mapping(address nft => mapping(uint256 round => mapping(uint256 index => bool))) public ghostIndexMinted;
    uint256 public ghostEthPaid;
    uint256 public ghostCoinPaid;
    uint256 public violations;
    string public lastViolation;
    mapping(string => uint256) public successes;

    struct PurchaseCtx {
        address nft;
        address payer;
        address recipient;
        uint256 round;
        Drop drop;
        DropPhase phase;
        uint256 n;
        uint256 cost;
        uint256 value;
        uint256 payerBefore;
        uint256 payoutBefore;
        uint256 feeBefore;
        uint256 recipientMintedBefore;
        uint256 totalSupplyBefore;
        uint256 protocolFee;
        uint256 sellerFeeBps;
        bool waived;
    }

    constructor() {
        stacks = new TLStacks721(address(this), address(0), feeReceiver, 0.001 ether, 250, 100);
        coin = new MockERC20(address(this));
        stacks.setCurrencyAllowed(address(coin), true);

        address[] memory empty = new address[](0);
        address[] memory minters = new address[](1);
        minters[0] = address(stacks);
        for (uint256 i = 0; i < 2; ++i) {
            ERC721TL nft = new ERC721TL(false);
            nft.initialize("Stacks", "STK", admin, 1_000, admin, empty, false, address(0), 0, address(0));
            vm.prank(admin);
            nft.setApprovedMintContracts(minters, true);
            nfts.push(address(nft));
        }

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));
        payoutReceivers.push(makeAddr("payoutA"));
        payoutReceivers.push(makeAddr("payoutB"));

        presaleAllowances = [uint256(1), 2, 3, 5];
        Merkle merkle = new Merkle();
        bytes32[] memory leaves = new bytes32[](actors.length);
        for (uint256 i = 0; i < actors.length; ++i) {
            leaves[i] =
                keccak256(bytes.concat(keccak256(abi.encode(keccak256(abi.encode(actors[i])), presaleAllowances[i]))));
            vm.prank(actors[i]);
            coin.approve(address(stacks), type(uint256).max);
        }
        presaleRoot = merkle.getRoot(leaves);
        for (uint256 i = 0; i < actors.length; ++i) {
            bytes32[] memory proof = merkle.getProof(leaves, i);
            for (uint256 j = 0; j < proof.length; ++j) {
                _proofs[i].push(proof[j]);
            }
        }
    }

    /////////////////////////////////////////////////////////////////////
    // DROP ADMIN ACTIONS
    /////////////////////////////////////////////////////////////////////

    function configureDrop(uint256 nftSeed, uint256 typeSeed, uint256 supply, uint256 seed) external {
        address nft = _pickNft(nftSeed, false);
        Drop memory drop = _randomDrop(typeSeed, supply, seed);
        Drop memory prev = stacks.getDrop(nft);
        DropPhase prevPhase = stacks.getDropPhase(nft);

        vm.prank(admin);
        try stacks.configureDrop(nft, drop) {
            _hit("configureDrop");
            _check(prev.dropType == DropType.NOT_CONFIGURED || prevPhase == DropPhase.ENDED, "G-48: live drop replaced");
            _check(drop.initialSupply == drop.supply, "G-46: uneven supply accepted");
            if (prev.dropType != DropType.NOT_CONFIGURED) ghostRound[nft]++;
            _check(stacks.getDropRound(nft) == ghostRound[nft], "configureDrop: round not bumped");
        } catch {}
    }

    function updateDropPayoutReceiver(uint256 nftSeed, uint256 receiverSeed) external {
        address nft = _nft(nftSeed);
        address receiver = payoutReceivers[receiverSeed % payoutReceivers.length];
        vm.prank(admin);
        try stacks.updateDropPayoutReceiver(nft, receiver) {
            _hit("updateDropPayoutReceiver");
            _check(stacks.getDrop(nft).payoutReceiver == receiver, "payout receiver not stored");
        } catch {}
    }

    function updateDropAllowance(uint256 nftSeed, uint256 allowance) external {
        address nft = _nft(nftSeed);
        allowance = _bound(allowance, 0, 10);
        vm.prank(admin);
        try stacks.updateDropAllowance(nft, allowance) {
            _hit("updateDropAllowance");
            _check(stacks.getDrop(nft).allowance == allowance, "allowance not stored");
        } catch {}
    }

    function updateDropPrices(uint256 nftSeed, bool useCoin, uint256 presaleCost, uint256 publicCost) external {
        address nft = _nft(nftSeed);
        presaleCost = _bound(presaleCost, 0, 1 ether);
        publicCost = _bound(publicCost, 0, 1 ether);
        vm.prank(admin);
        try stacks.updateDropPrices(nft, useCoin ? address(coin) : address(0), presaleCost, publicCost) {
            _hit("updateDropPrices");
        } catch {}
    }

    function updateDropDuration(uint256 nftSeed, uint256 startDelay, uint256 presaleDuration, uint256 publicDuration)
        external
    {
        address nft = _nft(nftSeed);
        uint256 startTime = _startTime(startDelay);
        presaleDuration = stacks.getDrop(nft).dropType == DropType.VELOCITY ? 0 : _bound(presaleDuration, 0, 2 days);
        publicDuration = _bound(publicDuration, 0, 3 days);
        vm.prank(admin);
        try stacks.updateDropDuration(nft, startTime, presaleDuration, publicDuration) {
            _hit("updateDropDuration");
        } catch {}
    }

    function updateDropPresaleMerkleRoot(uint256 nftSeed, bool useRealRoot) external {
        address nft = _nft(nftSeed);
        vm.prank(admin);
        try stacks.updateDropPresaleMerkleRoot(nft, useRealRoot ? presaleRoot : keccak256("junk")) {
            _hit("updateDropPresaleMerkleRoot");
        } catch {}
    }

    function updateDropDecayRate(uint256 nftSeed, int256 decayRate) external {
        address nft = _nft(nftSeed);
        decayRate = _bound(decayRate, -1 hours, 1 hours);
        vm.prank(admin);
        try stacks.updateDropDecayRate(nft, decayRate) {
            _hit("updateDropDecayRate");
        } catch {}
    }

    function updateDropSupply(uint256 nftSeed, uint256 newInitialSupply) external {
        address nft = _nft(nftSeed);
        Drop memory prev = stacks.getDrop(nft);
        uint256 minted = prev.initialSupply - prev.supply;
        // aim around the valid range [minted, initialSupply], including one step outside on each side
        newInitialSupply = _bound(newInitialSupply, minted == 0 ? 0 : minted - 1, prev.initialSupply + 1);

        vm.prank(admin);
        try stacks.updateDropSupply(nft, newInitialSupply) {
            _hit("updateDropSupply");
            Drop memory drop = stacks.getDrop(nft);
            _check(prev.dropType != DropType.SELECTABLE, "updateDropSupply on a selectable drop");
            _check(newInitialSupply >= minted && newInitialSupply <= prev.initialSupply, "G-61: supply outside range");
            _check(drop.initialSupply - drop.supply == minted, "updateDropSupply changed the minted count");
        } catch {}
    }

    /// @dev Closing always succeeds for the admin, so only one call in four goes through; otherwise drops would be
    ///      closed faster than they're configured and purchases would rarely find a live drop
    function closeDrop(uint256 nftSeed, uint256 gateSeed) external {
        if (gateSeed % 4 != 0) return;
        address nft = _nft(nftSeed);
        vm.prank(admin);
        try stacks.closeDrop(nft) {
            _hit("closeDrop");
            ghostRound[nft]++;
            _check(stacks.getDrop(nft).dropType == DropType.NOT_CONFIGURED, "closeDrop: drop not deleted");
            _check(stacks.getDropRound(nft) == ghostRound[nft], "closeDrop: round not bumped");
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // BUYER ACTIONS
    /////////////////////////////////////////////////////////////////////

    function purchase(uint256 nftSeed, uint256 payerSeed, uint256 recipientSeed, uint256 n, uint256 lieSeed) external {
        address nft = _pickNft(nftSeed, true);
        n = lieSeed % 8 == 1 ? _bound(n, 1, 5) : _bound(n, 1, _mintable(nft, recipientSeed));
        PurchaseCtx memory ctx = _ctx(nft, payerSeed, recipientSeed, n);
        bool lie = lieSeed % 8 == 0 && ctx.drop.currencyAddress == address(0);
        _fund(ctx.payer, ctx.drop.currencyAddress, ctx.value + 1);
        uint256 recipientIndex = recipientSeed % actors.length;
        ctx.payerBefore = _balance(ctx.payer, ctx.drop.currencyAddress);

        vm.prank(ctx.payer);
        try stacks.purchase{value: ctx.drop.currencyAddress == address(0) ? ctx.value + (lie ? 1 : 0) : 0}(
            ctx.nft,
            ctx.recipient,
            ctx.n,
            presaleAllowances[recipientIndex],
            _proofs[recipientIndex],
            ctx.drop.currencyAddress,
            ctx.cost,
            ctx.round
        ) {
            _hit("purchase");
            _check(!lie, "G-54: purchase accepted the wrong msg.value");
            _check(ctx.drop.dropType != DropType.SELECTABLE, "purchase minted a selectable drop");
            _checkPurchase(ctx);
            // non-selectable drops mint metadata indices in order from `initialSupply - supply`
            uint256 counter = ctx.drop.initialSupply - ctx.drop.supply;
            for (uint256 i = 0; i < ctx.n; ++i) {
                _check(_uriIs(ctx.nft, ctx.totalSupplyBefore + 1 + i, counter + i), "purchase: token uri out of order");
            }
        } catch {}
    }

    function purchaseSelected(uint256 nftSeed, uint256 payerSeed, uint256 recipientSeed, uint256 k, uint256 indexSeed)
        external
    {
        address nft = _pickNft(nftSeed, true);
        uint256[] memory indices = _pickIndices(
            nft, indexSeed % 8 == 1 ? _bound(k, 1, 4) : _bound(k, 1, _mintable(nft, recipientSeed)), indexSeed
        );
        PurchaseCtx memory ctx = _ctx(nft, payerSeed, recipientSeed, indices.length);
        _fund(ctx.payer, ctx.drop.currencyAddress, ctx.value);
        uint256 recipientIndex = recipientSeed % actors.length;
        ctx.payerBefore = _balance(ctx.payer, ctx.drop.currencyAddress);

        vm.prank(ctx.payer);
        try stacks.purchaseSelected{value: ctx.drop.currencyAddress == address(0) ? ctx.value : 0}(
            ctx.nft,
            ctx.recipient,
            indices,
            presaleAllowances[recipientIndex],
            _proofs[recipientIndex],
            ctx.drop.currencyAddress,
            ctx.cost,
            ctx.round
        ) {
            _hit("purchaseSelected");
            _check(ctx.drop.dropType == DropType.SELECTABLE, "purchaseSelected on a non-selectable drop");
            _checkPurchase(ctx);
            for (uint256 i = 0; i < indices.length; ++i) {
                _check(indices[i] < ctx.drop.initialSupply, "G-56: index out of range minted");
                _check(!ghostIndexMinted[nft][ctx.round][indices[i]], "G-57: index minted twice in a round");
                ghostIndexMinted[nft][ctx.round][indices[i]] = true;
                _check(stacks.isIndexMinted(nft, indices[i]), "index not marked");
                _check(_uriIs(nft, ctx.totalSupplyBefore + 1 + i, indices[i]), "selected token uri mismatch");
            }
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // TIME & OWNER
    /////////////////////////////////////////////////////////////////////

    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + _bound(secondsSeed, 0, 1 days));
        _hit("warp");
    }

    function setProtocolFeeSettings(uint256 protocolFee, uint256 ethBps, uint256 erc20Bps) external {
        protocolFee = _bound(protocolFee, 0, 0.01 ether);
        ethBps = _bound(ethBps, 0, 600);
        erc20Bps = _bound(erc20Bps, 0, 600);
        bool ok;
        try stacks.setProtocolFeeSettings(feeReceiver, protocolFee, ethBps, erc20Bps) {
            ok = true;
            _hit("setProtocolFeeSettings");
        } catch {}
        _check(ok == (ethBps <= 500 && erc20Bps <= 500), "G-44: seller fee cap not enforced");
    }

    function waiveSellerFee(uint256 nftSeed) external {
        address nft = _nft(nftSeed);
        stacks.waiveSellerFee(nft);
        ghostWaived[nft][ghostRound[nft]] = true;
        _hit("waiveSellerFee");
    }

    function setPaused(uint256 seed) external {
        try stacks.pause(seed % 8 == 0) {
            _hit("setPaused");
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // VIEWS FOR THE INVARIANT CONTRACT
    /////////////////////////////////////////////////////////////////////

    function numActors() external view returns (uint256) {
        return actors.length;
    }

    function numPayoutReceivers() external view returns (uint256) {
        return payoutReceivers.length;
    }

    /////////////////////////////////////////////////////////////////////
    // HELPERS
    /////////////////////////////////////////////////////////////////////

    function _randomDrop(uint256 typeSeed, uint256 supply, uint256 seed) internal view returns (Drop memory drop) {
        drop.dropType = typeSeed % 16 == 0 ? DropType.NOT_CONFIGURED : DropType(1 + typeSeed % 3); // rarely invalid
        drop.initialSupply = _bound(supply, 0, 300);
        drop.supply = seed % 16 == 0 ? drop.initialSupply + 1 : drop.initialSupply; // occasionally invalid
        drop.allowance = _bound(_word(seed, 0), 0, 10);
        drop.currencyAddress = _word(seed, 1) % 2 == 0 ? address(0) : address(coin);
        drop.payoutReceiver = payoutReceivers[_word(seed, 2) % payoutReceivers.length];
        drop.startTime = _startTime(_word(seed, 3));
        drop.presaleCost = _bound(_word(seed, 4), 0, 1 ether);
        drop.publicCost = _bound(_word(seed, 5), 0, 1 ether);
        drop.publicDuration = _bound(_word(seed, 6), 0, 3 days);
        drop.baseUri = BASE_URI;
        if (drop.dropType == DropType.VELOCITY) {
            drop.decayRate = int256(_bound(_word(seed, 7), 0, 2 hours)) - 1 hours;
        } else {
            drop.presaleDuration = _bound(_word(seed, 8), 0, 2 days);
            drop.presaleMerkleRoot = presaleRoot;
        }
    }

    /// @dev Snapshots everything a purchase is checked against. The cost is the current phase's price, sent as the
    ///      buyer's max cost so the pin is exercised at its boundary.
    function _ctx(address nft, uint256 payerSeed, uint256 recipientSeed, uint256 n)
        internal
        view
        returns (PurchaseCtx memory ctx)
    {
        ctx.nft = nft;
        ctx.payer = actors[payerSeed % actors.length];
        ctx.recipient = actors[recipientSeed % actors.length];
        ctx.round = stacks.getDropRound(nft);
        ctx.drop = stacks.getDrop(nft);
        ctx.phase = stacks.getDropPhase(nft);
        ctx.n = n;
        ctx.cost = ctx.phase == DropPhase.PRESALE ? ctx.drop.presaleCost : ctx.drop.publicCost;
        ctx.protocolFee = stacks.protocolFee();
        bool isEth = ctx.drop.currencyAddress == address(0);
        ctx.value = n * ctx.cost + (isEth ? n * ctx.protocolFee : 0);
        ctx.sellerFeeBps = isEth ? stacks.ethSellerFeeBps() : stacks.erc20SellerFeeBps();
        ctx.waived = stacks.isSellerFeeWaived(nft);
        ctx.payoutBefore = _balance(ctx.drop.payoutReceiver, ctx.drop.currencyAddress);
        ctx.feeBefore = _balance(feeReceiver, ctx.drop.currencyAddress);
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(nft, ctx.recipient);
        ctx.recipientMintedBefore = ctx.phase == DropPhase.PRESALE ? presaleMinted : publicMinted;
        ctx.totalSupplyBefore = ERC721TL(nft).totalSupply();
    }

    /// @dev E-2 split, exact payment, supply and per-wallet accounting, velocity duration, and mint count
    function _checkPurchase(PurchaseCtx memory ctx) internal {
        address currency = ctx.drop.currencyAddress;
        bool isEth = currency == address(0);
        uint256 totalSale = ctx.n * ctx.cost;
        uint256 sellerFee = ctx.waived ? 0 : totalSale * ctx.sellerFeeBps / BASIS;

        _check(
            _balance(ctx.drop.payoutReceiver, currency) == ctx.payoutBefore + totalSale - sellerFee,
            "E-2: payout receiver amount"
        );
        _check(
            _balance(feeReceiver, currency) == ctx.feeBefore + sellerFee + (isEth ? ctx.n * ctx.protocolFee : 0),
            "E-2: protocol fee receiver amount"
        );
        _check(_balance(ctx.payer, currency) + ctx.value == ctx.payerBefore, "G-54: payer charged a different amount");
        _check(ctx.phase == DropPhase.PRESALE || ctx.phase == DropPhase.PUBLIC_SALE, "minted outside a sale phase");

        Drop memory drop = stacks.getDrop(ctx.nft);
        _check(drop.supply + ctx.n == ctx.drop.supply, "supply not reduced by the number minted");
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(ctx.nft, ctx.recipient);
        _check(
            (ctx.phase == DropPhase.PRESALE ? presaleMinted : publicMinted) == ctx.recipientMintedBefore + ctx.n,
            "number minted not tracked"
        );
        _check(ERC721TL(ctx.nft).totalSupply() == ctx.totalSupplyBefore + ctx.n, "wrong number of tokens minted");

        if (ctx.drop.dropType == DropType.VELOCITY) {
            uint256 adjust = uint256(ctx.drop.decayRate < 0 ? -ctx.drop.decayRate : ctx.drop.decayRate) * ctx.n;
            uint256 expected = ctx.drop.decayRate < 0
                ? (adjust > ctx.drop.publicDuration ? 0 : ctx.drop.publicDuration - adjust)
                : ctx.drop.publicDuration + adjust;
            _check(drop.publicDuration == expected, "velocity duration adjustment");
        } else {
            _check(drop.publicDuration == ctx.drop.publicDuration, "non-velocity drop duration moved");
        }

        ghostMinted[ctx.nft] += ctx.n;
        if (isEth) ghostEthPaid += ctx.value;
        else ghostCoinPaid += ctx.value;
    }

    /// @dev What the recipient can still mint in the current phase (at least 1, capped at 5), so most purchases are
    ///      sized to succeed
    function _mintable(address nft, uint256 recipientSeed) internal view returns (uint256) {
        uint256 recipientIndex = recipientSeed % actors.length;
        Drop memory drop = stacks.getDrop(nft);
        DropPhase phase = stacks.getDropPhase(nft);
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(nft, actors[recipientIndex]);
        uint256 cap = phase == DropPhase.PRESALE ? presaleAllowances[recipientIndex] : drop.allowance;
        uint256 minted = phase == DropPhase.PRESALE ? presaleMinted : publicMinted;
        uint256 left = cap > minted ? cap - minted : 0;
        if (left > drop.supply) left = drop.supply;
        if (left > 5) left = 5;
        return left == 0 ? 1 : left;
    }

    /// @dev Mostly unminted indices in range; one call in eight uses raw indices that may repeat or be out of range
    function _pickIndices(address nft, uint256 k, uint256 seed) internal view returns (uint256[] memory indices) {
        uint256 initialSupply = stacks.getDrop(nft).initialSupply;
        indices = new uint256[](k);
        if (seed % 8 == 0 || initialSupply == 0) {
            for (uint256 i = 0; i < k; ++i) {
                indices[i] = _word(seed, i) % (initialSupply + 2);
            }
            return indices;
        }
        uint256 found;
        for (uint256 i = 0; i < initialSupply && found < k; ++i) {
            uint256 index = (seed % initialSupply + i) % initialSupply;
            if (!stacks.isIndexMinted(nft, index)) indices[found++] = index;
        }
        assembly {
            mstore(indices, found)
        }
    }

    function _uriIs(address nft, uint256 tokenId, uint256 index) internal view returns (bool) {
        return keccak256(bytes(ERC721TL(nft).tokenURI(tokenId)))
            == keccak256(abi.encodePacked(BASE_URI, "/", vm.toString(index)));
    }

    function _fund(address who, address currency, uint256 amount) internal {
        if (currency == address(0)) vm.deal(who, who.balance + amount);
        else coin.transfer(who, amount);
    }

    function _balance(address who, address currency) internal view returns (uint256) {
        return currency == address(0) ? who.balance : coin.balanceOf(who);
    }

    /// @dev Prefers a collection whose drop is in a sale phase (`live`) or can be reconfigured (`!live`); one call in
    ///      eight uses the raw seed so purchases outside a sale phase and reconfigures of live drops are still tried
    function _pickNft(uint256 seed, bool live) internal view returns (address) {
        if (seed % 8 == 0) return _nft(seed);
        for (uint256 i = 0; i < nfts.length; ++i) {
            address nft = nfts[(seed % nfts.length + i) % nfts.length];
            DropPhase phase = stacks.getDropPhase(nft);
            bool match_ = live
                ? phase == DropPhase.PRESALE || phase == DropPhase.PUBLIC_SALE
                : phase == DropPhase.NOT_CONFIGURED || phase == DropPhase.ENDED;
            if (match_) return nft;
        }
        return _nft(seed);
    }

    /// @dev A start time within a day either side of now, so updates don't keep pushing live drops back to not started
    function _startTime(uint256 seed) internal view returns (uint256) {
        uint256 offset = _bound(seed, 0, 2 days);
        return block.timestamp + offset > 1 days ? block.timestamp + offset - 1 days : 0;
    }

    function _nft(uint256 seed) internal view returns (address) {
        return nfts[seed % nfts.length];
    }

    function _word(uint256 seed, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, i)));
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

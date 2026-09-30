// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std-1.9.4/Test.sol";
import {ERC1155TL} from "tl-creator-contracts-4.1.1/erc-1155/ERC1155TL.sol";
import {TLStacks1155} from "src/TLStacks1155.sol";
import {Drop} from "src/utils/TLStacks1155Utils.sol";
import {DropPhase, DropType} from "src/utils/CommonUtils.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {Merkle} from "test/utils/murky/Merkle.sol";

/// @dev Drives TLStacks1155 through arbitrary interleavings of drop admin, buyer, and owner actions on three token ids
///      of one collection. Same structure as `Stacks721Handler`, keyed by token id and without selectable drops.
/// @dev Calls into the stacks contract are wrapped in try/catch so the handler never reverts (the suite runs with
///      `fail_on_revert = true`). Per-call properties are recorded as violations and checked by
///      `invariant_handlerAssertions`.
contract Stacks1155Handler is Test {
    uint256 internal constant BASIS = 10_000;
    uint256 public constant NUM_TOKENS = 3;

    TLStacks1155 public stacks;
    MockERC20 public coin;
    ERC1155TL public nft;
    address[] public actors; // buyers and recipients
    address[] public payoutReceivers; // disjoint from actors and the fee receiver
    address public admin = makeAddr("dropAdmin");
    address public feeReceiver = makeAddr("feeReceiver");

    bytes32 public presaleRoot;
    uint256[] public presaleAllowances; // per actor, the count in their merkle leaf
    mapping(uint256 actorIndex => bytes32[]) internal _proofs;

    // ghost state
    mapping(uint256 tokenId => uint256) public ghostRound;
    mapping(uint256 tokenId => mapping(uint256 round => bool)) public ghostWaived;
    mapping(uint256 tokenId => uint256) public ghostMinted; // across all rounds
    uint256 public ghostEthPaid;
    uint256 public ghostCoinPaid;
    uint256 public violations;
    string public lastViolation;
    mapping(string => uint256) public successes;

    struct PurchaseCtx {
        uint256 tokenId;
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
        uint256 recipientBalanceBefore;
        uint256 protocolFee;
        uint256 sellerFeeBps;
        bool waived;
    }

    constructor() {
        stacks = new TLStacks1155(address(this), address(0), feeReceiver, 0.001 ether, 250, 100);
        coin = new MockERC20(address(this));
        stacks.setCurrencyAllowed(address(coin), true);

        address[] memory empty = new address[](0);
        address[] memory minters = new address[](1);
        minters[0] = address(stacks);
        nft = new ERC1155TL(false);
        nft.initialize("Stacks", "STK", admin, 1_000, admin, empty, false, address(0), 0);
        address[] memory holders = new address[](1);
        holders[0] = admin;
        uint256[] memory amounts = new uint256[](1);
        vm.startPrank(admin);
        nft.setApprovedMintContracts(minters, true);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            nft.createToken("https://arweave.net/token", holders, amounts);
        }
        vm.stopPrank();

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

    function configureDrop(uint256 tokenSeed, uint256 typeSeed, uint256 supply, uint256 seed) external {
        uint256 tokenId = _pickToken(tokenSeed, false);
        Drop memory drop = _randomDrop(typeSeed, supply, seed);
        Drop memory prev = stacks.getDrop(address(nft), tokenId);
        DropPhase prevPhase = stacks.getDropPhase(address(nft), tokenId);

        vm.prank(admin);
        try stacks.configureDrop(address(nft), tokenId, drop) {
            _hit("configureDrop");
            _check(prev.dropType == DropType.NOT_CONFIGURED || prevPhase == DropPhase.ENDED, "G-49: live drop replaced");
            _check(drop.initialSupply == drop.supply, "G-47: uneven supply accepted");
            _check(drop.dropType != DropType.SELECTABLE, "selectable drop configured on 1155");
            if (prev.dropType != DropType.NOT_CONFIGURED) ghostRound[tokenId]++;
            _check(stacks.getDropRound(address(nft), tokenId) == ghostRound[tokenId], "configureDrop: round not bumped");
        } catch {}
    }

    function updateDropPayoutReceiver(uint256 tokenSeed, uint256 receiverSeed) external {
        uint256 tokenId = _tokenId(tokenSeed);
        address receiver = payoutReceivers[receiverSeed % payoutReceivers.length];
        vm.prank(admin);
        try stacks.updateDropPayoutReceiver(address(nft), tokenId, receiver) {
            _hit("updateDropPayoutReceiver");
            _check(stacks.getDrop(address(nft), tokenId).payoutReceiver == receiver, "payout receiver not stored");
        } catch {}
    }

    function updateDropAllowance(uint256 tokenSeed, uint256 allowance) external {
        uint256 tokenId = _tokenId(tokenSeed);
        allowance = _bound(allowance, 0, 10);
        vm.prank(admin);
        try stacks.updateDropAllowance(address(nft), tokenId, allowance) {
            _hit("updateDropAllowance");
            _check(stacks.getDrop(address(nft), tokenId).allowance == allowance, "allowance not stored");
        } catch {}
    }

    function updateDropPrices(uint256 tokenSeed, bool useCoin, uint256 presaleCost, uint256 publicCost) external {
        uint256 tokenId = _tokenId(tokenSeed);
        presaleCost = _bound(presaleCost, 0, 1 ether);
        publicCost = _bound(publicCost, 0, 1 ether);
        vm.prank(admin);
        try stacks.updateDropPrices(
            address(nft), tokenId, useCoin ? address(coin) : address(0), presaleCost, publicCost
        ) {
            _hit("updateDropPrices");
        } catch {}
    }

    function updateDropDuration(uint256 tokenSeed, uint256 startDelay, uint256 presaleDuration, uint256 publicDuration)
        external
    {
        uint256 tokenId = _tokenId(tokenSeed);
        uint256 startTime = _startTime(startDelay);
        presaleDuration = stacks.getDrop(address(nft), tokenId).dropType == DropType.VELOCITY
            ? 0
            : _bound(presaleDuration, 0, 2 days);
        publicDuration = _bound(publicDuration, 0, 3 days);
        vm.prank(admin);
        try stacks.updateDropDuration(address(nft), tokenId, startTime, presaleDuration, publicDuration) {
            _hit("updateDropDuration");
        } catch {}
    }

    function updateDropPresaleMerkleRoot(uint256 tokenSeed, bool useRealRoot) external {
        uint256 tokenId = _tokenId(tokenSeed);
        vm.prank(admin);
        try stacks.updateDropPresaleMerkleRoot(address(nft), tokenId, useRealRoot ? presaleRoot : keccak256("junk")) {
            _hit("updateDropPresaleMerkleRoot");
        } catch {}
    }

    function updateDropDecayRate(uint256 tokenSeed, int256 decayRate) external {
        uint256 tokenId = _tokenId(tokenSeed);
        decayRate = _bound(decayRate, -1 hours, 1 hours);
        vm.prank(admin);
        try stacks.updateDropDecayRate(address(nft), tokenId, decayRate) {
            _hit("updateDropDecayRate");
        } catch {}
    }

    function updateDropSupply(uint256 tokenSeed, uint256 newInitialSupply) external {
        uint256 tokenId = _tokenId(tokenSeed);
        Drop memory prev = stacks.getDrop(address(nft), tokenId);
        uint256 minted = prev.initialSupply - prev.supply;
        // aim around the valid range [minted, initialSupply], including one step outside on each side
        newInitialSupply = _bound(newInitialSupply, minted == 0 ? 0 : minted - 1, prev.initialSupply + 1);

        vm.prank(admin);
        try stacks.updateDropSupply(address(nft), tokenId, newInitialSupply) {
            _hit("updateDropSupply");
            Drop memory drop = stacks.getDrop(address(nft), tokenId);
            _check(newInitialSupply >= minted && newInitialSupply <= prev.initialSupply, "G-62: supply outside range");
            _check(drop.initialSupply - drop.supply == minted, "updateDropSupply changed the minted count");
        } catch {}
    }

    /// @dev Closing always succeeds for the admin, so only one call in four goes through; otherwise drops would be
    ///      closed faster than they're configured and purchases would rarely find a live drop
    function closeDrop(uint256 tokenSeed, uint256 gateSeed) external {
        if (gateSeed % 4 != 0) return;
        uint256 tokenId = _tokenId(tokenSeed);
        vm.prank(admin);
        try stacks.closeDrop(address(nft), tokenId) {
            _hit("closeDrop");
            ghostRound[tokenId]++;
            _check(
                stacks.getDrop(address(nft), tokenId).dropType == DropType.NOT_CONFIGURED, "closeDrop: drop not deleted"
            );
            _check(stacks.getDropRound(address(nft), tokenId) == ghostRound[tokenId], "closeDrop: round not bumped");
        } catch {}
    }

    /////////////////////////////////////////////////////////////////////
    // BUYER ACTIONS
    /////////////////////////////////////////////////////////////////////

    function purchase(uint256 tokenSeed, uint256 payerSeed, uint256 recipientSeed, uint256 n, uint256 lieSeed)
        external
    {
        uint256 tokenId = _pickToken(tokenSeed, true);
        n = lieSeed % 8 == 1 ? _bound(n, 1, 5) : _bound(n, 1, _mintable(tokenId, recipientSeed));
        PurchaseCtx memory ctx = _ctx(tokenId, payerSeed, recipientSeed, n);
        bool lie = lieSeed % 8 == 0 && ctx.drop.currencyAddress == address(0);
        _fund(ctx.payer, ctx.drop.currencyAddress, ctx.value + 1);
        uint256 recipientIndex = recipientSeed % actors.length;
        ctx.payerBefore = _balance(ctx.payer, ctx.drop.currencyAddress);

        vm.prank(ctx.payer);
        try stacks.purchase{value: ctx.drop.currencyAddress == address(0) ? ctx.value + (lie ? 1 : 0) : 0}(
            address(nft),
            tokenId,
            ctx.recipient,
            ctx.n,
            presaleAllowances[recipientIndex],
            _proofs[recipientIndex],
            ctx.drop.currencyAddress,
            ctx.cost,
            ctx.round
        ) {
            _hit("purchase");
            _check(!lie, "G-55: purchase accepted the wrong msg.value");
            _checkPurchase(ctx);
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
        _check(ok == (ethBps <= 500 && erc20Bps <= 500), "G-45: seller fee cap not enforced");
    }

    function waiveSellerFee(uint256 tokenSeed) external {
        uint256 tokenId = _tokenId(tokenSeed);
        stacks.waiveSellerFee(address(nft), tokenId);
        ghostWaived[tokenId][ghostRound[tokenId]] = true;
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
        // selectable is only supported on 721, so it is one of the rarely chosen invalid types here
        drop.dropType = typeSeed % 8 == 0 ? DropType(typeSeed % 16 == 0 ? 0 : 3) : DropType(1 + typeSeed % 2);
        drop.initialSupply = _bound(supply, 0, 300);
        drop.supply = seed % 16 == 0 ? drop.initialSupply + 1 : drop.initialSupply; // occasionally invalid
        drop.allowance = _bound(_word(seed, 0), 0, 10);
        drop.currencyAddress = _word(seed, 1) % 2 == 0 ? address(0) : address(coin);
        drop.payoutReceiver = payoutReceivers[_word(seed, 2) % payoutReceivers.length];
        drop.startTime = _startTime(_word(seed, 3));
        drop.presaleCost = _bound(_word(seed, 4), 0, 1 ether);
        drop.publicCost = _bound(_word(seed, 5), 0, 1 ether);
        drop.publicDuration = _bound(_word(seed, 6), 0, 3 days);
        if (drop.dropType == DropType.VELOCITY) {
            drop.decayRate = int256(_bound(_word(seed, 7), 0, 2 hours)) - 1 hours;
        } else {
            drop.presaleDuration = _bound(_word(seed, 8), 0, 2 days);
            drop.presaleMerkleRoot = presaleRoot;
        }
    }

    /// @dev Snapshots everything a purchase is checked against. The cost is the current phase's price, sent as the
    ///      buyer's max cost so the pin is exercised at its boundary.
    function _ctx(uint256 tokenId, uint256 payerSeed, uint256 recipientSeed, uint256 n)
        internal
        view
        returns (PurchaseCtx memory ctx)
    {
        ctx.tokenId = tokenId;
        ctx.payer = actors[payerSeed % actors.length];
        ctx.recipient = actors[recipientSeed % actors.length];
        ctx.round = stacks.getDropRound(address(nft), tokenId);
        ctx.drop = stacks.getDrop(address(nft), tokenId);
        ctx.phase = stacks.getDropPhase(address(nft), tokenId);
        ctx.n = n;
        ctx.cost = ctx.phase == DropPhase.PRESALE ? ctx.drop.presaleCost : ctx.drop.publicCost;
        ctx.protocolFee = stacks.protocolFee();
        bool isEth = ctx.drop.currencyAddress == address(0);
        ctx.value = n * ctx.cost + (isEth ? n * ctx.protocolFee : 0);
        ctx.sellerFeeBps = isEth ? stacks.ethSellerFeeBps() : stacks.erc20SellerFeeBps();
        ctx.waived = stacks.isSellerFeeWaived(address(nft), tokenId);
        ctx.payoutBefore = _balance(ctx.drop.payoutReceiver, ctx.drop.currencyAddress);
        ctx.feeBefore = _balance(feeReceiver, ctx.drop.currencyAddress);
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(address(nft), tokenId, ctx.recipient);
        ctx.recipientMintedBefore = ctx.phase == DropPhase.PRESALE ? presaleMinted : publicMinted;
        ctx.recipientBalanceBefore = nft.balanceOf(ctx.recipient, tokenId);
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
        _check(_balance(ctx.payer, currency) + ctx.value == ctx.payerBefore, "G-55: payer charged a different amount");
        _check(ctx.phase == DropPhase.PRESALE || ctx.phase == DropPhase.PUBLIC_SALE, "minted outside a sale phase");

        Drop memory drop = stacks.getDrop(address(nft), ctx.tokenId);
        _check(drop.supply + ctx.n == ctx.drop.supply, "supply not reduced by the number minted");
        (uint256 presaleMinted, uint256 publicMinted) = stacks.getNumberMinted(address(nft), ctx.tokenId, ctx.recipient);
        _check(
            (ctx.phase == DropPhase.PRESALE ? presaleMinted : publicMinted) == ctx.recipientMintedBefore + ctx.n,
            "number minted not tracked"
        );
        _check(
            nft.balanceOf(ctx.recipient, ctx.tokenId) == ctx.recipientBalanceBefore + ctx.n,
            "recipient did not receive the tokens"
        );

        if (ctx.drop.dropType == DropType.VELOCITY) {
            uint256 adjust = uint256(ctx.drop.decayRate < 0 ? -ctx.drop.decayRate : ctx.drop.decayRate) * ctx.n;
            uint256 expected = ctx.drop.decayRate < 0
                ? (adjust > ctx.drop.publicDuration ? 0 : ctx.drop.publicDuration - adjust)
                : ctx.drop.publicDuration + adjust;
            _check(drop.publicDuration == expected, "velocity duration adjustment");
        } else {
            _check(drop.publicDuration == ctx.drop.publicDuration, "non-velocity drop duration moved");
        }

        ghostMinted[ctx.tokenId] += ctx.n;
        if (isEth) ghostEthPaid += ctx.value;
        else ghostCoinPaid += ctx.value;
    }

    /// @dev What the recipient can still mint in the current phase (at least 1, capped at 5), so most purchases are
    ///      sized to succeed
    function _mintable(uint256 tokenId, uint256 recipientSeed) internal view returns (uint256) {
        uint256 recipientIndex = recipientSeed % actors.length;
        Drop memory drop = stacks.getDrop(address(nft), tokenId);
        DropPhase phase = stacks.getDropPhase(address(nft), tokenId);
        (uint256 presaleMinted, uint256 publicMinted) =
            stacks.getNumberMinted(address(nft), tokenId, actors[recipientIndex]);
        uint256 cap = phase == DropPhase.PRESALE ? presaleAllowances[recipientIndex] : drop.allowance;
        uint256 minted = phase == DropPhase.PRESALE ? presaleMinted : publicMinted;
        uint256 left = cap > minted ? cap - minted : 0;
        if (left > drop.supply) left = drop.supply;
        if (left > 5) left = 5;
        return left == 0 ? 1 : left;
    }

    /// @dev Prefers a token whose drop is in a sale phase (`live`) or can be reconfigured (`!live`); one call in
    ///      eight uses the raw seed so purchases outside a sale phase and reconfigures of live drops are still tried
    function _pickToken(uint256 seed, bool live) internal view returns (uint256) {
        if (seed % 8 == 0) return _tokenId(seed);
        for (uint256 i = 0; i < NUM_TOKENS; ++i) {
            uint256 tokenId = _tokenId(seed % NUM_TOKENS + i);
            DropPhase phase = stacks.getDropPhase(address(nft), tokenId);
            bool match_ = live
                ? phase == DropPhase.PRESALE || phase == DropPhase.PUBLIC_SALE
                : phase == DropPhase.NOT_CONFIGURED || phase == DropPhase.ENDED;
            if (match_) return tokenId;
        }
        return _tokenId(seed);
    }

    /// @dev A start time within a day either side of now, so updates don't keep pushing live drops back to not started
    function _startTime(uint256 seed) internal view returns (uint256) {
        uint256 offset = _bound(seed, 0, 2 days);
        return block.timestamp + offset > 1 days ? block.timestamp + offset - 1 days : 0;
    }

    function _fund(address who, address currency, uint256 amount) internal {
        if (currency == address(0)) vm.deal(who, who.balance + amount);
        else coin.transfer(who, amount);
    }

    function _balance(address who, address currency) internal view returns (uint256) {
        return currency == address(0) ? who.balance : coin.balanceOf(who);
    }

    function _tokenId(uint256 seed) internal pure returns (uint256) {
        return seed % NUM_TOKENS + 1;
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

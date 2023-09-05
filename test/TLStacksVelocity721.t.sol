// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";
// import {VyperDeployer} from "utils/VyperDeployer.sol";

// import {ITLStacksVelocity721Events, ITLStacksVelocity721, Drop} from "tl-stacks/utils/ITLStacksVelocity721.sol";
// import {DropPhase, DropParam} from "tl-stacks/utils/DropUtils.sol";

// import {TLCreator} from "tl-creator-contracts/TLCreator.sol";
// import {ERC721TL} from "tl-creator-contracts/core/ERC721TL.sol";
// import {NotSpecifiedRole} from "tl-sol-tools/upgradeable/access/OwnableAccessControlUpgradeable.sol";

// import {Receiver} from "./utils/Receiver.sol";
// import {MockERC20} from "./utils/MockERC20.sol";

// contract TLStacksVelocity721Test is Test, ITLStacksVelocity721Events {
//     bytes32 constant MINTER_ROLE = keccak256("APPROVED_MINT_CONTRACT");
//     bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

//     VyperDeployer vyperDeployer = new VyperDeployer();

//     ITLStacksVelocity721 stacks;
//     ERC721TL nft;
//     ERC721TL nftTwo;
//     MockERC20 coin;

//     address nftOwner = address(0xABC);
//     address receiver;

//     address ben = address(0x0BEEF);
//     address chris = address(0xC0FFEE);
//     address david = address(0x1D1B);
//     address bsy = address(0xCDB);

//     function setUp() public {
//         stacks = ITLStacksVelocity721(vyperDeployer.deployContract("TLStacksVelocity721", abi.encode(address(this))));

//         address[] memory empty = new address[](0);
//         address[] memory mintAddrs = new address[](1);
//         mintAddrs[0] = address(stacks);

//         ERC721TL implementation = new ERC721TL(true);
//         TLCreator proxy = new TLCreator(
//             address(implementation),
//             "Test ERC721",
//             "LFG",
//             nftOwner,
//             1_000,
//             nftOwner,
//             empty,
//             false,
//             address(0)
//         );
//         nft = ERC721TL(address(proxy));
//         vm.prank(nftOwner);
//         nft.setApprovedMintContracts(mintAddrs, true);

//         coin = new MockERC20(address(this));
//         coin.transfer(ben, 100 ether);
//         coin.transfer(chris, 100 ether);
//         coin.transfer(david, 100 ether);
//         coin.transfer(bsy, 100 ether);

//         receiver = address(new Receiver());

//         vm.deal(ben, 100 ether);
//         vm.deal(chris, 100 ether);
//         vm.deal(david, 100 ether);
//         vm.deal(bsy, 100 ether);

//         TLCreator proxyTwo = new TLCreator(
//             address(implementation),
//             "Test ERC721 2",
//             "LFG2",
//             nftOwner,
//             1_000,
//             nftOwner,
//             empty,
//             false,
//             address(0)
//         );
//         nftTwo = ERC721TL(address(proxyTwo));
//         vm.prank(nftOwner);
//         nftTwo.setApprovedMintContracts(mintAddrs, true);
//     }

//     /// @dev test constructor setup
//     function test_setUp() public {
//         assert(stacks.owner() == address(this));
//         assertFalse(stacks.paused());
//         assertTrue(nft.hasRole(MINTER_ROLE, address(stacks)));
//     }

//     /// @dev test owner only access for owner functions
//     /// @dev reverts if not the owner
//     function test_owner_only_access(address sender) public {
//         vm.assume(sender != address(this));
//         vm.startPrank(sender);
//         vm.expectRevert("caller not owner");
//         stacks.set_paused(true);
//         vm.expectRevert("caller not owner");
//         stacks.set_paused(false);
//         vm.expectRevert("caller not owner");
//         stacks.transfer_ownership(sender);
//         vm.stopPrank();
//     }

//     /// @dev check ownership transfer
//     /// @dev should emit an event log for ownership transferred
//     /// @dev new owner is reflected in state
//     /// @dev reverts when old owner tries to do something
//     function test_transfer_ownership(address newOwner) public {
//         vm.assume(newOwner != address(this));
//         vm.expectEmit(true, true, false, false);
//         emit OwnershipTransferred(address(this), newOwner);
//         stacks.transfer_ownership(newOwner);
//         assert(stacks.owner() == newOwner);
//         vm.expectRevert("caller not owner");
//         stacks.set_paused(true);
//     }

//     /// @dev verifies that drop admins or contract owner can access drop write functions
//     /// @dev reverts when `notDropAdmin` calls the functions
//     function test_drop_admin_access(address dropAdmin, address notDropAdmin) public {
//         vm.assume(dropAdmin != nftOwner);
//         vm.assume(notDropAdmin != nftOwner);
//         vm.assume(dropAdmin != notDropAdmin);

//         // test contract owner
//         vm.startPrank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             10,
//             -1
//         );
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
//         stacks.close_drop(address(nft));
//         address[] memory admins = new address[](1);
//         admins[0] = dropAdmin;
//         nft.setRole(ADMIN_ROLE, admins, true);
//         vm.stopPrank();

//         // test contract admin
//         vm.startPrank(dropAdmin);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             10,
//             -1
//         );
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
//         stacks.close_drop(address(nft));
//         nft.renounceRole(ADMIN_ROLE);
//         vm.stopPrank();

//         // test not admin or contract owner
//         vm.startPrank(notDropAdmin);
//         vm.expectRevert("not authorized");
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             10,
//             -1
//         );
//         vm.expectRevert("not authorized");
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(7200)));
//         vm.expectRevert("not authorized");
//         stacks.close_drop(address(nft));
//         vm.stopPrank();
//     }

//     /// @dev checks that pausing blocks all necessary functions
//     /// @dev pauses regardless of function caller
//     function test_paused(address caller) public {
//         stacks.set_paused(true);

//         vm.startPrank(caller);
//         vm.expectRevert("contract is paused");
//         stacks.configure_drop(address(1), "baseuri", 100, 1, address(0), address(1), 100, 100, 1, -1);
//         vm.expectRevert("contract is paused");
//         stacks.close_drop(address(1));
//         vm.expectRevert("contract is paused");
//         stacks.update_drop_param(address(1), DropPhase.PUBLIC_SALE, DropParam.DURATION, bytes32(uint256(100)));
//         vm.expectRevert("contract is paused");
//         stacks.mint(address(1), 1, address(2));

//         vm.stopPrank();

//         stacks.set_paused(false);
//     }

//     /// @dev tests `configure_drop` with eth
//     /// @dev checks reverting cases as well
//     /// @dev checks emitted event
//     function test_configure_drop_eth(
//         string memory baseUri,
//         uint256 supply,
//         uint256 allowance,
//         address payoutReceiver,
//         uint256 startTime,
//         uint256 duration,
//         uint256 cost,
//         int256 decayRate
//     ) public {
//         vm.startPrank(nftOwner);

//         bool doesNotRevert = false;

//         if (startTime == 0) {
//             vm.expectRevert("start time cannot be zero");
//         } else if (decayRate == 0) {
//             vm.expectRevert("decay rate cannot be zero");
//         } else if (duration == 0) {
//             vm.expectRevert("duration cannot be zero");
//         } else {
//             doesNotRevert = true;
//             vm.expectEmit(true, true, true, false);
//             emit DropConfigured(nftOwner, address(nft), block.number);
//         }

//         stacks.configure_drop(
//             address(nft),
//             baseUri,
//             supply,
//             allowance,
//             address(0),
//             payoutReceiver,
//             startTime,
//             duration,
//             cost,
//             decayRate
//         );

//         if (doesNotRevert) {
//             Drop memory drop = stacks.get_drop(address(nft));
//             assertEq(drop.base_uri, baseUri);
//             assertEq(drop.initial_supply, supply);
//             assertEq(drop.supply, supply);
//             assertEq(drop.allowance, allowance);
//             assertEq(drop.currency_addr, address(0));
//             assertEq(drop.payout_receiver, payoutReceiver);
//             assertEq(drop.start_time, startTime);
//             assertEq(drop.duration, duration);
//             assertEq(drop.cost, cost);
//             assertEq(drop.decay_rate, decayRate);
//         }

//         vm.stopPrank();
//     }

//     /// @dev tests `configure_drop` with erc20
//     /// @dev checks reverting cases as well
//     /// @dev checks emitted event
//     function test_configure_drop_erc20(
//         string memory baseUri,
//         uint256 supply,
//         uint256 allowance,
//         address payoutReceiver,
//         uint256 startTime,
//         uint256 duration,
//         uint256 cost,
//         int256 decayRate
//     ) public {
//         vm.startPrank(nftOwner);

//         bool doesNotRevert = false;

//         if (startTime == 0) {
//             vm.expectRevert("start time cannot be zero");
//         } else if (decayRate == 0) {
//             vm.expectRevert("decay rate cannot be zero");
//         } else if (duration == 0) {
//             vm.expectRevert("duration cannot be zero");
//         } else {
//             doesNotRevert = true;
//             vm.expectEmit(true, true, true, false);
//             emit DropConfigured(nftOwner, address(nft), block.number);
//         }

//         stacks.configure_drop(
//             address(nft),
//             baseUri,
//             supply,
//             allowance,
//             address(coin),
//             payoutReceiver,
//             startTime,
//             duration,
//             cost,
//             decayRate
//         );

//         if (doesNotRevert) {
//             Drop memory drop = stacks.get_drop(address(nft));
//             assertEq(drop.base_uri, baseUri);
//             assertEq(drop.initial_supply, supply);
//             assertEq(drop.supply, supply);
//             assertEq(drop.allowance, allowance);
//             assertEq(drop.currency_addr, address(coin));
//             assertEq(drop.payout_receiver, payoutReceiver);
//             assertEq(drop.start_time, startTime);
//             assertEq(drop.duration, duration);
//             assertEq(drop.cost, cost);
//             assertEq(drop.decay_rate, decayRate);
//         }

//         vm.stopPrank();
//     }

//     /// @dev tests `close_drop`
//     /// @dev verifies proper event is emitted
//     /// @dev verifies reset Drop
//     /// @dev verifies drop round increased
//     function test_close_drop() public {
//         vm.startPrank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             10,
//             -1
//         );
//         uint256 prevRound = stacks.get_drop_round(address(nft));

//         vm.expectEmit(true, true, false, false);
//         emit DropClosed(nftOwner, address(nft));
//         stacks.close_drop(address(nft));

//         uint256 currRound = stacks.get_drop_round(address(nft));

//         assertEq(currRound, prevRound + 1);

//         vm.stopPrank();
//     }

//     /// @dev tests `update_drop_param`
//     /// @dev verifies event emittance
//     /// @dev verifies reverting cases
//     function test_update_drop_param(bytes32 paramValue) public {
//         vm.startPrank(nftOwner);

//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0,
//             -1
//         );

//         // allowance
//         vm.expectEmit(true, true, false, true);
//         emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.ALLOWANCE, paramValue);
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.ALLOWANCE, paramValue);
//         // cost
//         vm.expectEmit(true, true, false, true);
//         emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.COST, paramValue);
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.COST, paramValue);
//         // duration
//         vm.expectEmit(true, true, false, true);
//         emit DropUpdated(nftOwner, address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, paramValue);
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.DURATION, paramValue);
//         // start time
//         vm.expectEmit(true, true, false, true);
//         emit DropUpdated(nftOwner, address(nft), DropPhase.BEFORE_SALE, DropParam.START_TIME, paramValue);
//         stacks.update_drop_param(address(nft), DropPhase.BEFORE_SALE, DropParam.START_TIME, paramValue);

//         // expect revert
//         vm.expectRevert("unknown param update");
//         stacks.update_drop_param(address(nft), DropPhase.PRESALE, DropParam.START_TIME, paramValue);
//         vm.expectRevert("unknown param update");
//         stacks.update_drop_param(address(nft), DropPhase.PUBLIC_SALE, DropParam.MERKLE_ROOT, paramValue);
//         vm.expectRevert("unknown param update");
//         stacks.update_drop_param(address(nft), DropPhase.BEFORE_SALE, DropParam.COST, paramValue);
//         vm.expectRevert("unknown param update");
//         stacks.update_drop_param(address(nft), DropPhase.NOT_CONFIGURED, DropParam.COST, paramValue);

//         // check updated params
//         Drop memory drop = stacks.get_drop(address(nft));
//         assertEq(drop.allowance, uint256(paramValue));
//         assertEq(drop.start_time, uint256(paramValue));
//         assertEq(drop.duration, uint256(paramValue));
//         assertEq(drop.cost, uint256(paramValue));

//         vm.stopPrank();
//     }

//     /// @dev test mint zero tokens
//     function test_mint_zero_tokens() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0,
//             -1
//         );

//         vm.expectRevert("cannot mint zero tokens");
//         stacks.mint(address(nft), 0, address(this));
//     }

//     /// @dev test mint not approved mint contract
//     function test_mint_not_approved_mint_contract() public {
//         vm.startPrank(nftOwner);
//         address[] memory addys = new address[](1);
//         addys[0] = address(stacks);
//         nft.setRole(MINTER_ROLE, addys, false);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0,
//             -1
//         );
//         vm.stopPrank();

//         vm.expectRevert(abi.encodeWithSelector(NotSpecifiedRole.selector, MINTER_ROLE));
//         stacks.mint(address(nft), 1, address(this));

//         vm.prank(nftOwner);
//         nft.setRole(MINTER_ROLE, addys, true);
//     }

//     /// @dev test supply == 0
//     function test_mint_zero_supply() public {
//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, address(this));
//     }

//     /// @dev not enough eth sent
//     function test_not_enough_eth_sent() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             1 ether,
//             -1
//         );

//         vm.prank(ben);
//         vm.expectRevert("insufficient funds");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, ben);
//     }

//     /// @dev test not enough erc20 allowance given
//     function test_not_enough_allowance_given() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             1 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         coin.approve(address(stacks), 0.1 ether);
//         vm.expectRevert("insufficient funds");
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();
//     }

//     /// @dev test not enough erc20 balance
//     function test_not_enough_balance() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             1,
//             address(coin),
//             nftOwner,
//             block.timestamp,
//             3600,
//             101 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         coin.approve(address(stacks), 1000 ether);
//         vm.expectRevert("insufficient funds");
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();
//     }

//     /// @dev mint more than allowance and get limited to allowance
//     function test_mint_allowance() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             4,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         uint256 prevBalance = ben.balance;
//         stacks.mint{value: 0.005 ether}(address(nft), 5, ben);
//         assert(prevBalance - ben.balance == 0.004 ether);
//         assert(nft.balanceOf(ben) == 4);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();
//     }

//     /// @dev mint more than supply left and get limited to supply left
//     function test_mint_more_than_supply() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             4,
//             5,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         uint256 prevBalance = ben.balance;
//         stacks.mint{value: 0.005 ether}(address(nft), 5, ben);
//         assert(prevBalance - ben.balance == 0.004 ether);
//         assert(nft.balanceOf(ben) == 4);
//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();
//     }

//     /// @dev test mint amount that drives duration to 0
//     function test_mint_past_duration() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             4,
//             5,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0 ether,
//             -1 hours
//         );

//         vm.startPrank(ben);
//         stacks.mint(address(nft), 5, ben);
//         assert(nft.balanceOf(ben) == 4);
//         uint256 dropPhase = stacks.get_drop_phase(address(nft));
//         assert(dropPhase == DropPhase.ENDED);
//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();
//     }

//     /// @dev test send more eth than needed and get refunded extra eth
//     function test_mint_too_much_eth() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             5,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         uint256 prevBalance = ben.balance;
//         stacks.mint{value: 0.005 ether}(address(nft), 1, ben);
//         assert(prevBalance - ben.balance == 0.001 ether);
//         assert(nft.balanceOf(ben) == 1);

//         vm.stopPrank();
//     }

//     /// @dev test eth sent with erc20 and get refunded
//     function test_mint_erc20_with_eth() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             5,
//             address(coin),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         coin.approve(address(stacks), 0.001 ether);
//         uint256 prevBalance = ben.balance;
//         uint256 prevCoin = coin.balanceOf(ben);
//         stacks.mint{value: 0.001 ether}(address(nft), 1, ben);
//         assert(prevBalance - ben.balance == 0);
//         assert(nft.balanceOf(ben) == 1);
//         assert(prevCoin - coin.balanceOf(ben) == 0.001 ether);
//         vm.stopPrank();
//     }

//     /// @dev test mint for someone else and yourself
//     function test_mint_for_someone_else() public {
//         // eth
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             5,
//             address(0),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         uint256 prevETHBalance = ben.balance;
//         stacks.mint{value: 0.001 ether}(address(nft), 1, chris);
//         stacks.mint{value: 0.001 ether}(address(nft), 1, david);
//         stacks.mint{value: 0.001 ether}(address(nft), 1, ben);
//         vm.stopPrank();

//         assert(nft.balanceOf(chris) == 1);
//         assert(nft.balanceOf(david) == 1);
//         assert(nft.balanceOf(ben) == 1);
//         assert(prevETHBalance - ben.balance == 0.003 ether);
//         assert(stacks.get_num_minted(address(nft), chris) == 1);
//         assert(stacks.get_num_minted(address(nft), david) == 1);
//         assert(stacks.get_num_minted(address(nft), ben) == 1);

//         vm.prank(nftOwner);
//         stacks.close_drop(address(nft));

//         // erc20
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://art.transientlabs.xyz",
//             100,
//             5,
//             address(coin),
//             nftOwner,
//             block.timestamp,
//             3600,
//             0.001 ether,
//             -1
//         );

//         vm.startPrank(ben);
//         uint256 prevERC20Balance = coin.balanceOf(ben);
//         coin.approve(address(stacks), 100 ether);
//         stacks.mint(address(nft), 1, chris);
//         stacks.mint(address(nft), 1, david);
//         stacks.mint(address(nft), 1, ben);
//         vm.stopPrank();

//         assert(nft.balanceOf(chris) == 2);
//         assert(nft.balanceOf(david) == 2);
//         assert(nft.balanceOf(ben) == 2);
//         assert(prevERC20Balance - coin.balanceOf(ben) == 0.003 ether);
//         assert(stacks.get_num_minted(address(nft), chris) == 1);
//         assert(stacks.get_num_minted(address(nft), david) == 1);
//         assert(stacks.get_num_minted(address(nft), ben) == 1);
//     }

//     /// @dev test eth velocity mint
//     function test_eth_velocity_mint() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             25,
//             address(0),
//             receiver,
//             block.timestamp + 3600,
//             100 minutes,
//             0.1 ether,
//             -1 minutes
//         );

//         // pre-drop
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));

//         // cache drop
//         Drop memory drop = stacks.get_drop(address(nft));

//         vm.warp(drop.start_time);

//         uint256 minterBalance = ben.balance;
//         uint256 receiverBalance = receiver.balance;

//         // ben
//         vm.startPrank(ben);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, ben);
//         assert(nft.balanceOf(ben) == 20);
//         assert(minterBalance - ben.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postBenDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBenDrop.duration == 20 minutes);
//         assert(postBenDrop.supply == 80);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, ben);
//         assert(nft.balanceOf(ben) == 25);
//         assert(minterBalance - ben.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postBenDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBenDrop.duration == 25 minutes);
//         assert(postBenDrop.supply == 75);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, ben);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // chris
//         vm.startPrank(chris);
//         minterBalance = chris.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, chris);
//         assert(nft.balanceOf(chris) == 20);
//         assert(minterBalance - chris.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postChrisDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postChrisDrop.duration == 20 minutes);
//         assert(postChrisDrop.supply == 55);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, chris);
//         assert(nft.balanceOf(chris) == 25);
//         assert(minterBalance - chris.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postChrisDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postChrisDrop.duration == 25 minutes);
//         assert(postChrisDrop.supply == 50);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, chris);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // david
//         vm.startPrank(david);
//         minterBalance = david.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, david);
//         assert(nft.balanceOf(david) == 20);
//         assert(minterBalance - david.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postDavidDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postDavidDrop.duration == 20 minutes);
//         assert(postDavidDrop.supply == 30);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, david);
//         assert(nft.balanceOf(david) == 25);
//         assert(minterBalance - david.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postDavidDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postDavidDrop.duration == 25 minutes);
//         assert(postDavidDrop.supply == 25);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, david);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // bsy
//         vm.startPrank(bsy);
//         minterBalance = bsy.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, bsy);
//         assert(nft.balanceOf(bsy) == 20);
//         assert(minterBalance - bsy.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postBsyDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBsyDrop.duration == 20 minutes);
//         assert(postBsyDrop.supply == 5);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, bsy);
//         assert(nft.balanceOf(bsy) == 25);
//         assert(minterBalance - bsy.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postBsyDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBsyDrop.duration == 25 minutes);
//         assert(postBsyDrop.supply == 0);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, bsy);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // final checks
//         uint256 dropPhase = stacks.get_drop_phase(address(nft));
//         assertEq(drop.duration, 0);
//         assertEq(drop.supply, 0);
//         assertEq(dropPhase, DropPhase.ENDED);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));
//     }

//     /// @dev test eth marathon mint
//     function test_eth_marathon_mint() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             25,
//             address(0),
//             receiver,
//             block.timestamp + 3600,
//             100 minutes,
//             0.1 ether,
//             1 minutes
//         );

//         // pre-drop
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));

//         // cache drop
//         Drop memory drop = stacks.get_drop(address(nft));

//         vm.warp(drop.start_time);

//         uint256 minterBalance = ben.balance;
//         uint256 receiverBalance = receiver.balance;

//         // ben
//         vm.startPrank(ben);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, ben);
//         assert(nft.balanceOf(ben) == 20);
//         assert(minterBalance - ben.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postBenDrop = stacks.get_drop(address(nft));
//         assert(postBenDrop.duration - drop.duration == 20 minutes);
//         assert(postBenDrop.supply == 80);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, ben);
//         assert(nft.balanceOf(ben) == 25);
//         assert(minterBalance - ben.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postBenDrop = stacks.get_drop(address(nft));
//         assert(postBenDrop.duration - drop.duration == 25 minutes);
//         assert(postBenDrop.supply == 75);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, ben);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // chris
//         vm.startPrank(chris);
//         minterBalance = chris.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, chris);
//         assert(nft.balanceOf(chris) == 20);
//         assert(minterBalance - chris.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postChrisDrop = stacks.get_drop(address(nft));
//         assert(postChrisDrop.duration - drop.duration == 20 minutes);
//         assert(postChrisDrop.supply == 55);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, chris);
//         assert(nft.balanceOf(chris) == 25);
//         assert(minterBalance - chris.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postChrisDrop = stacks.get_drop(address(nft));
//         assert(postChrisDrop.duration - drop.duration == 25 minutes);
//         assert(postChrisDrop.supply == 50);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, chris);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // david
//         vm.startPrank(david);
//         minterBalance = david.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, david);
//         assert(nft.balanceOf(david) == 20);
//         assert(minterBalance - david.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postDavidDrop = stacks.get_drop(address(nft));
//         assert(postDavidDrop.duration - drop.duration == 20 minutes);
//         assert(postDavidDrop.supply == 30);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, david);
//         assert(nft.balanceOf(david) == 25);
//         assert(minterBalance - david.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postDavidDrop = stacks.get_drop(address(nft));
//         assert(postDavidDrop.duration - drop.duration == 25 minutes);
//         assert(postDavidDrop.supply == 25);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, david);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // bsy
//         vm.startPrank(bsy);
//         minterBalance = bsy.balance;
//         receiverBalance = receiver.balance;
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(0), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, bsy);
//         assert(nft.balanceOf(bsy) == 20);
//         assert(minterBalance - bsy.balance == 2 ether);
//         assert(receiver.balance - receiverBalance == 2 ether);
//         Drop memory postBsyDrop = stacks.get_drop(address(nft));
//         assert(postBsyDrop.duration - drop.duration == 20 minutes);
//         assert(postBsyDrop.supply == 5);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(0), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, bsy);
//         assert(nft.balanceOf(bsy) == 25);
//         assert(minterBalance - bsy.balance == 2.5 ether);
//         assert(receiver.balance - receiverBalance == 2.5 ether);
//         postBsyDrop = stacks.get_drop(address(nft));
//         assert(postBsyDrop.duration - drop.duration == 25 minutes);
//         assert(postBsyDrop.supply == 0);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, bsy);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // final checks
//         uint256 dropPhase = stacks.get_drop_phase(address(nft));
//         assertEq(drop.duration, 200 minutes);
//         assertEq(drop.supply, 0);
//         assertEq(dropPhase, DropPhase.ENDED);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));
//     }

//     /// @dev test erc20 velocity mint
//     function test_erc20_velocity_mint() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             25,
//             address(coin),
//             receiver,
//             block.timestamp + 3600,
//             100 minutes,
//             0.1 ether,
//             -1 minutes
//         );

//         // pre-drop
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));

//         // cache drop
//         Drop memory drop = stacks.get_drop(address(nft));

//         vm.warp(drop.start_time);

//         uint256 ethBalance = ben.balance;
//         uint256 minterBalance = coin.balanceOf(ben);
//         uint256 receiverBalance = coin.balanceOf(receiver);

//         // ben
//         vm.startPrank(ben);
//         coin.approve(address(stacks), 100 ether);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, ben);
//         assert(nft.balanceOf(ben) == 20);
//         assert(minterBalance - coin.balanceOf(ben) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postBenDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBenDrop.duration == 20 minutes);
//         assert(postBenDrop.supply == 80);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, ben);
//         assert(nft.balanceOf(ben) == 25);
//         assert(minterBalance - coin.balanceOf(ben) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postBenDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBenDrop.duration == 25 minutes);
//         assert(postBenDrop.supply == 75);
//         assert(ben.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, ben);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // chris
//         vm.startPrank(chris);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = chris.balance;
//         minterBalance = coin.balanceOf(chris);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, chris);
//         assert(nft.balanceOf(chris) == 20);
//         assert(minterBalance - coin.balanceOf(chris) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postChrisDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postChrisDrop.duration == 20 minutes);
//         assert(postChrisDrop.supply == 55);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, chris);
//         assert(nft.balanceOf(chris) == 25);
//         assert(minterBalance - coin.balanceOf(chris) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postChrisDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postChrisDrop.duration == 25 minutes);
//         assert(postChrisDrop.supply == 50);
//         assert(chris.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, chris);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // david
//         vm.startPrank(david);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = david.balance;
//         minterBalance = coin.balanceOf(david);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, david);
//         assert(nft.balanceOf(david) == 20);
//         assert(minterBalance - coin.balanceOf(david) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postDavidDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postDavidDrop.duration == 20 minutes);
//         assert(postDavidDrop.supply == 30);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, david);
//         assert(nft.balanceOf(david) == 25);
//         assert(minterBalance - coin.balanceOf(david) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postDavidDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postDavidDrop.duration == 25 minutes);
//         assert(postDavidDrop.supply == 25);
//         assert(david.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, david);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // bsy
//         vm.startPrank(bsy);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = bsy.balance;
//         minterBalance = coin.balanceOf(bsy);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, bsy);
//         assert(nft.balanceOf(bsy) == 20);
//         assert(minterBalance - coin.balanceOf(bsy) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postBsyDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBsyDrop.duration == 20 minutes);
//         assert(postBsyDrop.supply == 5);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, bsy);
//         assert(nft.balanceOf(bsy) == 25);
//         assert(minterBalance - coin.balanceOf(bsy) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postBsyDrop = stacks.get_drop(address(nft));
//         assert(drop.duration - postBsyDrop.duration == 25 minutes);
//         assert(postBsyDrop.supply == 0);
//         assert(bsy.balance == ethBalance);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, bsy);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // final checks
//         uint256 dropPhase = stacks.get_drop_phase(address(nft));
//         assertEq(drop.duration, 0);
//         assertEq(drop.supply, 0);
//         assertEq(dropPhase, DropPhase.ENDED);
//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, address(this));
//     }

//     /// @dev test erc20 marathon mint
//     function test_erc20_marathon_mint() public {
//         vm.prank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             25,
//             address(coin),
//             receiver,
//             block.timestamp + 3600,
//             100 minutes,
//             0.1 ether,
//             1 minutes
//         );

//         // pre-drop
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, address(this));

//         // cache drop
//         Drop memory drop = stacks.get_drop(address(nft));

//         vm.warp(drop.start_time);

//         uint256 ethBalance = ben.balance;
//         uint256 minterBalance = coin.balanceOf(ben);
//         uint256 receiverBalance = coin.balanceOf(receiver);

//         // ben
//         vm.startPrank(ben);
//         coin.approve(address(stacks), 100 ether);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, ben);
//         assert(nft.balanceOf(ben) == 20);
//         assert(minterBalance - coin.balanceOf(ben) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postBenDrop = stacks.get_drop(address(nft));
//         assert(postBenDrop.duration - drop.duration == 20 minutes);
//         assert(postBenDrop.supply == 80);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(ben, ben, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, ben);
//         assert(nft.balanceOf(ben) == 25);
//         assert(minterBalance - coin.balanceOf(ben) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postBenDrop = stacks.get_drop(address(nft));
//         assert(postBenDrop.duration - drop.duration == 25 minutes);
//         assert(postBenDrop.supply == 75);
//         assert(ben.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, ben);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // chris
//         vm.startPrank(chris);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = chris.balance;
//         minterBalance = coin.balanceOf(chris);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, chris);
//         assert(nft.balanceOf(chris) == 20);
//         assert(minterBalance - coin.balanceOf(chris) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postChrisDrop = stacks.get_drop(address(nft));
//         assert(postChrisDrop.duration - drop.duration == 20 minutes);
//         assert(postChrisDrop.supply == 55);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(chris, chris, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, chris);
//         assert(nft.balanceOf(chris) == 25);
//         assert(minterBalance - coin.balanceOf(chris) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postChrisDrop = stacks.get_drop(address(nft));
//         assert(postChrisDrop.duration - drop.duration == 25 minutes);
//         assert(postChrisDrop.supply == 50);
//         assert(chris.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, chris);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // david
//         vm.startPrank(david);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = david.balance;
//         minterBalance = coin.balanceOf(david);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, david);
//         assert(nft.balanceOf(david) == 20);
//         assert(minterBalance - coin.balanceOf(david) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postDavidDrop = stacks.get_drop(address(nft));
//         assert(postDavidDrop.duration - drop.duration == 20 minutes);
//         assert(postDavidDrop.supply == 30);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(david, david, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, david);
//         assert(nft.balanceOf(david) == 25);
//         assert(minterBalance - coin.balanceOf(david) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postDavidDrop = stacks.get_drop(address(nft));
//         assert(postDavidDrop.duration - drop.duration == 25 minutes);
//         assert(postDavidDrop.supply == 25);
//         assert(david.balance == ethBalance);
//         vm.expectRevert("already hit mint allowance");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, david);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // bsy
//         vm.startPrank(bsy);
//         coin.approve(address(stacks), 100 ether);
//         ethBalance = bsy.balance;
//         minterBalance = coin.balanceOf(bsy);
//         receiverBalance = coin.balanceOf(receiver);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(coin), 20, 0.1 ether);
//         stacks.mint{value: 2.1 ether}(address(nft), 20, bsy);
//         assert(nft.balanceOf(bsy) == 20);
//         assert(minterBalance - coin.balanceOf(bsy) == 2 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2 ether);
//         Drop memory postBsyDrop = stacks.get_drop(address(nft));
//         assert(postBsyDrop.duration - drop.duration == 20 minutes);
//         assert(postBsyDrop.supply == 5);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(bsy, bsy, address(nft), address(coin), 5, 0.1 ether);
//         stacks.mint{value: 0.5 ether}(address(nft), 5, bsy);
//         assert(nft.balanceOf(bsy) == 25);
//         assert(minterBalance - coin.balanceOf(bsy) == 2.5 ether);
//         assert(coin.balanceOf(receiver) - receiverBalance == 2.5 ether);
//         postBsyDrop = stacks.get_drop(address(nft));
//         assert(postBsyDrop.duration - drop.duration == 25 minutes);
//         assert(postBsyDrop.supply == 0);
//         assert(bsy.balance == ethBalance);
//         vm.expectRevert("you shall not mint");
//         stacks.mint{value: 0.1 ether}(address(nft), 1, bsy);
//         vm.stopPrank();

//         // re-cache drop
//         drop = stacks.get_drop(address(nft));

//         // final checks
//         uint256 dropPhase = stacks.get_drop_phase(address(nft));
//         assertEq(drop.duration, 200 minutes);
//         assertEq(drop.supply, 0);
//         assertEq(dropPhase, DropPhase.ENDED);
//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, address(this));
//     }

//     /// @dev test eth mint fuzz
//     function test_eth_mint_fuzz(
//         uint256 allowance,
//         uint256 startDelay,
//         uint256 duration,
//         uint256 cost,
//         int256 decayRate,
//         address minter
//     ) public {
//         vm.assume(allowance > 0);
//         vm.assume(duration > 0);
//         vm.assume(decayRate != 0 && decayRate != type(int256).min);
//         vm.assume(minter != address(0) && minter != address(this));

//         uint256 absDecayRate = decayRate < 0 ? uint256(0 - decayRate) : uint256(decayRate);

//         if (cost > 10 ether) {
//             cost = cost % 10 ether;
//         }

//         if (allowance > 10) {
//             allowance = allowance % 10 + 1;
//         }

//         if (startDelay > 3650 days) {
//             startDelay = startDelay % 3650 days;
//         }

//         if (duration > 3650 days) {
//             duration = duration % 3650 days;
//         }

//         if (absDecayRate > 100 days && decayRate > 0) {
//             decayRate = decayRate % 100 days + 1;
//             absDecayRate = uint256(decayRate);
//         }

//         if (absDecayRate > 100 days && decayRate < 0) {
//             decayRate = decayRate % 100 days - 1;
//             absDecayRate = uint256(0 - decayRate);
//         }

//         vm.deal(minter, 100 ether);

//         vm.startPrank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             allowance,
//             address(0),
//             receiver,
//             block.timestamp + startDelay,
//             duration,
//             cost,
//             decayRate
//         );
//         vm.stopPrank();

//         Drop memory drop = stacks.get_drop(address(nft));

//         // test before sale
//         if (startDelay > 0) {
//             vm.expectRevert("you shall not mint");
//             stacks.mint(address(nft), 1, address(this));
//             vm.warp(drop.start_time);
//         }

//         // test sale
//         vm.startPrank(minter);
//         uint256 recipientBalance = minter.balance;
//         uint256 payoutBalance = receiver.balance;
//         uint256 nftBalance = nft.balanceOf(minter);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(minter, minter, address(nft), address(0), allowance, cost);
//         stacks.mint{value: allowance * cost}(address(nft), allowance, minter);
//         assert(nft.balanceOf(minter) - nftBalance == allowance);
//         assert(recipientBalance - minter.balance == allowance * cost);
//         assert(receiver.balance - payoutBalance == allowance * cost);
//         Drop memory dropPostMint = stacks.get_drop(address(nft));
//         if (absDecayRate * allowance >= drop.duration && decayRate < 0) {
//             assert(dropPostMint.duration == 0);
//         } else {
//             if (decayRate < 0) {
//                 assert(dropPostMint.duration == drop.duration - allowance * absDecayRate);
//             } else {
//                 assert(dropPostMint.duration == drop.duration + allowance * absDecayRate);
//             }
//         }

//         vm.stopPrank();

//         if (drop.start_time + dropPostMint.duration > block.timestamp) {
//             vm.warp(drop.start_time + dropPostMint.duration);
//         }

//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, address(this));
//     }

//     /// @dev test erc20 mint fuzz
//     function test_erc20_mint_fuzz(
//         uint256 allowance,
//         uint256 startDelay,
//         uint256 duration,
//         uint256 cost,
//         int256 decayRate,
//         address minter
//     ) public {
//         vm.assume(allowance > 0);
//         vm.assume(duration > 0);
//         vm.assume(decayRate != 0 && decayRate != type(int256).min);
//         vm.assume(minter != address(0) && minter != address(this));

//         uint256 absDecayRate = decayRate < 0 ? uint256(0 - decayRate) : uint256(decayRate);

//         if (cost > 10 ether) {
//             cost = cost % 10 ether;
//         }

//         if (allowance > 10) {
//             allowance = allowance % 10 + 1;
//         }

//         if (startDelay > 3650 days) {
//             startDelay = startDelay % 3650 days;
//         }

//         if (duration > 3650 days) {
//             duration = duration % 3650 days;
//         }

//         if (absDecayRate > 100 days && decayRate > 0) {
//             decayRate = decayRate % 100 days + 1;
//             absDecayRate = uint256(decayRate);
//         }

//         if (absDecayRate > 100 days && decayRate < 0) {
//             decayRate = decayRate % 100 days - 1;
//             absDecayRate = uint256(0 - decayRate);
//         }

//         coin.transfer(minter, 100 ether);

//         vm.startPrank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net",
//             100,
//             allowance,
//             address(coin),
//             receiver,
//             block.timestamp + startDelay,
//             duration,
//             cost,
//             decayRate
//         );
//         vm.stopPrank();

//         Drop memory drop = stacks.get_drop(address(nft));

//         // test before sale
//         if (startDelay > 0) {
//             vm.expectRevert("you shall not mint");
//             stacks.mint(address(nft), 1, address(this));
//             vm.warp(drop.start_time);
//         }

//         // test sale
//         vm.startPrank(minter);
//         coin.approve(address(stacks), 100 ether);
//         uint256 recipientBalance = coin.balanceOf(minter);
//         uint256 payoutBalance = coin.balanceOf(receiver);
//         uint256 nftBalance = nft.balanceOf(minter);
//         vm.expectEmit(true, true, true, true);
//         emit Purchase(minter, minter, address(nft), address(coin), allowance, cost);
//         stacks.mint(address(nft), allowance, minter);
//         assert(nft.balanceOf(minter) - nftBalance == allowance);
//         assert(recipientBalance - coin.balanceOf(minter) == allowance * cost);
//         assert(coin.balanceOf(receiver) - payoutBalance == allowance * cost);
//         Drop memory dropPostMint = stacks.get_drop(address(nft));
//         if (absDecayRate * allowance >= drop.duration && decayRate < 0) {
//             assert(dropPostMint.duration == 0);
//         } else {
//             if (decayRate < 0) {
//                 assert(dropPostMint.duration == drop.duration - allowance * absDecayRate);
//             } else {
//                 assert(dropPostMint.duration == drop.duration + allowance * absDecayRate);
//             }
//         }

//         vm.stopPrank();

//         if (drop.start_time + dropPostMint.duration > block.timestamp) {
//             vm.warp(drop.start_time + dropPostMint.duration);
//         }

//         vm.expectRevert("you shall not mint");
//         stacks.mint(address(nft), 1, address(this));
//     }

//     /// @dev test two mints going on at the same time on separate contracts
//     function test_two_mints_going_on_simultaneously() public {
//         vm.startPrank(nftOwner);
//         stacks.configure_drop(
//             address(nft),
//             "https://arweave.net/1",
//             100,
//             10,
//             address(0),
//             receiver,
//             block.timestamp,
//             3600,
//             0,
//             -100
//         );

//         stacks.configure_drop(
//             address(nftTwo),
//             "https://arweave.net/2",
//             100,
//             10,
//             address(0),
//             receiver,
//             block.timestamp + 3600,
//             3600,
//             0,
//             -1
//         );
//         vm.stopPrank();

//         assert(stacks.get_drop_phase(address(nft)) == DropPhase.PUBLIC_SALE);
//         assert(stacks.get_drop_phase(address(nftTwo)) == DropPhase.BEFORE_SALE);

//         stacks.mint(address(nft), 1, address(this));
//         assert(stacks.get_num_minted(address(nft), address(this)) == 1);
//         assert(stacks.get_num_minted(address(nftTwo), address(this)) == 0);

//         vm.warp(block.timestamp + 3600);

//         assert(stacks.get_drop_phase(address(nft)) == DropPhase.ENDED);
//         assert(stacks.get_drop_phase(address(nftTwo)) == DropPhase.PUBLIC_SALE);

//         stacks.mint(address(nftTwo), 5, address(this));

//         assert(stacks.get_num_minted(address(nft), address(this)) == 1);
//         assert(stacks.get_num_minted(address(nftTwo), address(this)) == 5);
//     }
// }

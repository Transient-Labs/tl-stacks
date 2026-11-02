// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std-1.9.4/Test.sol";
import {Ownable, RoyaltyLookup, IRoyaltyEngineV1} from "src/helpers/RoyaltyLookup.sol";
import {ERC721TL, ERC2981TLUpgradeable} from "tl-creator-contracts-4.1.1/erc-721/ERC721TL.sol";
import {MalformedRoyaltyNFT} from "test/utils/AuditRecoveryMocks.sol";

contract RoyaltyLookupTest is Test {
    RoyaltyLookup rl;
    ERC721TL nft;

    address badNft = makeAddr("badddd");

    function setUp() public {
        rl = new RoyaltyLookup(address(this));

        address[] memory empty = new address[](0);
        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", address(this), 1_000, address(this), empty, false, address(0), 0, address(0));
    }

    function test_setRoyaltyEngine_accessControl(address hacker) public {
        vm.assume(hacker != address(this));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        vm.prank(hacker);
        rl.setRoyaltyEngine(hacker);
    }

    function test_getRoyalty_noRoyaltyEngine(address fakeNft, uint256 tokenId) public {
        vm.assume(fakeNft != address(nft) && fakeNft != badNft);

        address payable[] memory recipients;
        uint256[] memory amounts;

        // fake nft
        (recipients, amounts) = rl.getRoyalty(fakeNft, tokenId, 10_000);
        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);

        (recipients, amounts) = rl.getRoyaltyView(fakeNft, tokenId, 10_000);
        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);

        // bad nft
        vm.mockCallRevert(
            badNft, abi.encodeWithSelector(ERC2981TLUpgradeable.royaltyInfo.selector, tokenId, 10_000), "revert"
        );
        (recipients, amounts) = rl.getRoyalty(badNft, tokenId, 10_000);
        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);
        vm.clearMockedCalls();

        vm.mockCallRevert(
            badNft, abi.encodeWithSelector(ERC2981TLUpgradeable.royaltyInfo.selector, tokenId, 10_000), "revert"
        );
        (recipients, amounts) = rl.getRoyaltyView(badNft, tokenId, 10_000);
        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);
        vm.clearMockedCalls();

        // real nft
        (recipients, amounts) = rl.getRoyalty(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        (recipients, amounts) = rl.getRoyaltyView(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);
    }

    /// @dev A malformed successful response can't be caught where it is decoded, so the lookup reverts;
    ///      `TLAuctionHouse` calls the helper inside `try/catch` and pays no royalty
    function test_malformedDirectResponsesRevertLookup(bool withEngine) public {
        if (withEngine) rl.setRoyaltyEngine(address(this)); // engine call reverts, so the helper goes direct
        MalformedRoyaltyNFT token = new MalformedRoyaltyNFT();
        for (uint8 mode; mode < 3; ++mode) {
            token.setMode(mode);
            vm.expectRevert();
            rl.getRoyalty(address(token), 1, 10_000);
            vm.expectRevert();
            rl.getRoyaltyView(address(token), 1, 10_000);
        }
        token.setMode(3);
        (address payable[] memory r, uint256[] memory a) = rl.getRoyalty(address(token), 1, 10_000);
        assertEq(r[0], address(0xBEEF));
        assertEq(a[0], 1_000);
        (r, a) = rl.getRoyaltyView(address(token), 1, 10_000);
        assertEq(r[0], address(0xBEEF));
        assertEq(a[0], 1_000);
    }

    function test_engineScheduleToZeroRecipientFallsBack() public {
        rl.setRoyaltyEngine(address(this));
        address payable[] memory er = new address payable[](1); // zero-address recipient
        uint256[] memory ea = new uint256[](1);
        ea[0] = 5_000;
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector), abi.encode(er, ea));
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyaltyView.selector), abi.encode(er, ea));
        (address payable[] memory r, uint256[] memory a) = rl.getRoyalty(address(nft), 1, 10_000);
        assertEq(r[0], address(this));
        assertEq(a[0], 1_000);
        (r, a) = rl.getRoyaltyView(address(nft), 1, 10_000);
        assertEq(r[0], address(this));
        assertEq(a[0], 1_000);
    }

    function test_pending_emptyAndZeroEngineFallsBack() public {
        rl.setRoyaltyEngine(address(this));
        for (uint256 length; length < 3; ++length) {
            address payable[] memory r = new address payable[](length);
            uint256[] memory a = new uint256[](length);
            if (length > 0) r[0] = payable(badNft);
            vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector), abi.encode(r, a));
            vm.mockCall(
                address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyaltyView.selector), abi.encode(r, a)
            );
            (address payable[] memory actual, uint256[] memory amounts) = rl.getRoyalty(address(nft), 1, 10_000);
            assertEq(actual[0], address(this));
            assertEq(amounts[0], 1_000);
            (actual, amounts) = rl.getRoyaltyView(address(nft), 1, 10_000);
            assertEq(actual[0], address(this));
            assertEq(amounts[0], 1_000);
        }
    }

    function test_getRoyalty_royaltyEngine(uint256 tokenId) public {
        address payable[] memory recipients;
        uint256[] memory amounts;

        // set royalty engine to EOA
        rl.setRoyaltyEngine(address(420));

        // Invalid engine falls back to the direct contract royalty
        (recipients, amounts) = rl.getRoyalty(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        (recipients, amounts) = rl.getRoyaltyView(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        // set royalty to a contract and mock different states
        rl.setRoyaltyEngine(address(this));

        // reverting call
        vm.mockCallRevert(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector), "revert");
        vm.mockCallRevert(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyaltyView.selector), "revert");

        (recipients, amounts) = rl.getRoyalty(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        (recipients, amounts) = rl.getRoyaltyView(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        vm.clearMockedCalls();

        // mismatch in addresses
        address payable[] memory r = new address payable[](2);
        r[0] = payable(address(0));
        r[1] = payable(address(1));
        uint256[] memory a = new uint256[](1);
        a[0] = 1_000;
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector), abi.encode(r, a));
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyaltyView.selector), abi.encode(r, a));

        (recipients, amounts) = rl.getRoyalty(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        (recipients, amounts) = rl.getRoyaltyView(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], address(this));
        assertEq(amounts[0], 1_000);

        vm.clearMockedCalls();

        // success
        r = new address payable[](2);
        r[0] = payable(address(0));
        r[1] = payable(address(1));
        a = new uint256[](2);
        a[0] = 900;
        a[1] = 100;
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyalty.selector), abi.encode(r, a));
        vm.mockCall(address(this), abi.encodeWithSelector(IRoyaltyEngineV1.getRoyaltyView.selector), abi.encode(r, a));

        (recipients, amounts) = rl.getRoyalty(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 2);
        assertEq(amounts.length, 2);
        assertEq(recipients[0], address(0));
        assertEq(recipients[1], address(1));
        assertEq(amounts[0], 900);
        assertEq(amounts[1], 100);

        (recipients, amounts) = rl.getRoyaltyView(address(nft), tokenId, 10_000);
        assertEq(recipients.length, 2);
        assertEq(amounts.length, 2);
        assertEq(recipients[0], address(0));
        assertEq(recipients[1], address(1));
        assertEq(amounts[0], 900);
        assertEq(amounts[1], 100);

        vm.clearMockedCalls();
    }
}

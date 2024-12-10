// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {CreatorLookup, Ownable} from "src/helpers/CreatorLookup.sol";
import {ERC721TL} from "tl-creator-contracts/erc-721/ERC721TL.sol";

contract CreatorLookupTest is Test {
    CreatorLookup cl;
    ERC721TL nft;

    function setUp() public {
        cl = new CreatorLookup();

        address[] memory empty = new address[](0);
        nft = new ERC721TL(false);
        nft.initialize("LFG Bro", "LFG", "", address(this), 1_000, address(this), empty, false, address(0), address(0));
    }

    function test_getCreator(address fakeNft, uint256 tokenId) public {
        vm.assume(fakeNft != address(nft) && fakeNft.code.length == 0);

        // fake nft
        address fakeResult = cl.getCreator(fakeNft, tokenId);
        assertEq(fakeResult, address(0));

        // reverting contract
        vm.mockCallRevert(fakeNft, Ownable.owner.selector, "revert");
        fakeResult = cl.getCreator(fakeNft, tokenId);
        assertEq(fakeResult, address(0));
        vm.clearMockedCalls();

        // real nft
        address result = cl.getCreator(address(nft), tokenId);
        assertEq(result, address(this));
    }
}

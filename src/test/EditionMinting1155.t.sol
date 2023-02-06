// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";

import {IEditionMinting1155} from "../IEditionMinting1155.sol";

contract EditionMinting1155Test is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();

    IEditionMinting1155 mintingContract;

    address mintingOwner = address(0xdead);

    address alice = address(0xbeef);
    address bob = address(0x1337);
    address charles = address(0xcafe);

    function setUp() public {
        mintingContract = IEditionMinting1155(
            vyperDeployer.deployContract("EditionMinting1155", abi.encode(mintingOwner))
        );
    }

    function test_init() public view {
        address owner = mintingContract.owner();
        assert(owner == mintingOwner);
    }
}

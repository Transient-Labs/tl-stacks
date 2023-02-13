// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {Script} from "forge-std/Script.sol";

import {TLSimpleSaleFactory} from "tl-stacks/fiat/TLSimpleSaleFactory.sol";

contract TLSimpleSaleFactoryScript is Script {
    function run(address owner) external {
        vm.startBroadcast();

        TLSimpleSaleFactory saleFactory = new TLSimpleSaleFactory(owner);

        vm.stopBroadcast();
    }
}

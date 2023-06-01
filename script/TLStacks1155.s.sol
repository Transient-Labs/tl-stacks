// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";
import {ITLStacks1155} from "tl-stacks/ITLStacks1155.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract TLStacks1155Script is Script {
    function run(address sender, string calldata rpc, address owner) external {
        // VyperDeployer vyperDeployer = new VyperDeployer();

        vm.startBroadcast();

        string[] memory vyperInput = new string[](2);
        vyperInput[0] = "vyper";
        vyperInput[1] = "vyper_contracts/TLStacks1155.vy";

        bytes memory bytecode = vm.ffi(vyperInput);

        string[] memory input = new string[](9);
        input[0] = "cast";
        input[1] = "send";
        input[2] = "--rpc-url";
        input[3] = rpc;
        input[4] = "--from";
        input[5] = vm.toString(sender);
        input[6] = "--create";
        input[7] = vm.toString(bytecode);
        input[8] = vm.toString(abi.encode(owner));

        vm.ffi(input);

        // address stacks1155 = vyperDeployer.deployContract(
        //     "TLStacks1155",
        //     abi.encode(owner)
        // );

        // assert(owner == IOwnable(stacks1155).owner());

        vm.stopBroadcast();
    }
}

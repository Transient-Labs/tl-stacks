// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {Script} from "forge-std/Script.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";
import {ITLStacks1155} from "tl-stacks/ITLStacks1155.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract TLStacks1155Script is Script {
    function run() external {
        VyperDeployer vyperDeployer = new VyperDeployer();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address stacks1155 = vyperDeployer.deployContract(
            "TLStacks1155",
            abi.encode(msg.sender)
        );

        assert(msg.sender == IOwnable(stacks1155).owner());

        vm.stopBroadcast();
    }
}

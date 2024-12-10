// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";

interface ICreate2Deployer {
    function deploy(uint256 value, bytes32 salt, bytes memory code) external;
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}

// contract DeployTLAuctionHouse is Script {
//     using Strings for address;

//     function run() public {
//         // get environment variables
//         ICreate2Deployer create2Deployer = ICreate2Deployer(vm.envAddress("CREATE2_DEPLOYER"));
//         bytes memory constructorArgs = vm.envBytes("CONSTRUCTOR_ARGS");
//         bytes32 salt = vm.envBytes32("SALT");

//         // get bytecode
//         bytes memory bytecode = abi.encodePacked(vm.getCode("TLAuctionHouse.sol:TLAuctionHouse"), constructorArgs);

//         // deploy
//         address deployedContract = create2Deployer.computeAddress(salt, keccak256(bytecode));
//         console.logAddress(deployedContract);
//         vm.broadcast();
//         create2Deployer.deploy(0, salt, bytecode);

//         // save deployed contract address
//         vm.writeLine("out.txt", deployedContract.toHexString());
//     }
// }

contract DeployTLStacks721 is Script {
    using Strings for address;

    function run() public {
        // get environment variables
        ICreate2Deployer create2Deployer = ICreate2Deployer(vm.envAddress("CREATE2_DEPLOYER"));
        bytes memory constructorArgs = vm.envBytes("CONSTRUCTOR_ARGS");
        bytes32 salt = vm.envBytes32("SALT");

        // get bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("TLStacks721.sol:TLStacks721"), constructorArgs);

        // deploy
        address deployedContract = create2Deployer.computeAddress(salt, keccak256(bytecode));
        console.logAddress(deployedContract);
        vm.broadcast();
        create2Deployer.deploy(0, salt, bytecode);

        // save deployed contract address
        vm.writeLine("out.txt", deployedContract.toHexString());
    }
}

contract DeployTLStacks1155 is Script {
    using Strings for address;

    function run() public {
        // get environment variables
        ICreate2Deployer create2Deployer = ICreate2Deployer(vm.envAddress("CREATE2_DEPLOYER"));
        bytes memory constructorArgs = vm.envBytes("CONSTRUCTOR_ARGS");
        bytes32 salt = vm.envBytes32("SALT");

        // get bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("TLStacks1155.sol:TLStacks1155"), constructorArgs);

        // deploy
        address deployedContract = create2Deployer.computeAddress(salt, keccak256(bytecode));
        console.logAddress(deployedContract);
        vm.broadcast();
        create2Deployer.deploy(0, salt, bytecode);

        // save deployed contract address
        vm.writeLine("out.txt", deployedContract.toHexString());
    }
}

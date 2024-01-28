// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TLAuctionHouse} from "src/TLAuctionHouse.sol";
import {TLStacks721} from "src/TLStacks721.sol";
import {TLStacks1155} from "src/TLStacks1155.sol";

contract Deployments is Script {
    // these variables are defined and exported .env file
    address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
    address wethAddress = vm.envAddress("WETH_ADDRESS");
    address protocolFeeReceiver = vm.envAddress("PROTOCOL_FEE_RECEIVER");
    uint256 stacksFee = vm.envUint("STACKS_FEE");
    address royaltyEngineAddress = vm.envAddress("ROYALTY_ENGINE_ADDRESS");
    uint256 minBidIncreasePerc = vm.envUint("MIN_BID_INCREASE_PERC");
    uint256 minBidIncreaseLimit = vm.envUint("MIN_BID_INCREASE_LIMIT");
    uint256 ahFeePerc = vm.envUint("AH_FEE_PERC");
    uint256 ahFeeLimit = vm.envUint("AH_FEE_LIMIT");

    function deployTLStacks721() public {
        vm.broadcast();
        new TLStacks721(sanctionsOracle, wethAddress, protocolFeeReceiver, stacksFee);
    }

    function deployTLStacks1155() public {
        vm.broadcast();
        new TLStacks1155(sanctionsOracle, wethAddress, protocolFeeReceiver, stacksFee);
    }

    function deployTLAuctionHouse() public {
        vm.broadcast();
        new TLAuctionHouse(sanctionsOracle, wethAddress, royaltyEngineAddress, protocolFeeReceiver, minBidIncreasePerc, minBidIncreaseLimit, ahFeePerc, ahFeeLimit);
    }
}

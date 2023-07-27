// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Receiver {
    event EthReceived(uint256 indexed amount);

    receive() external payable {
        emit EthReceived(msg.value);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("hehe sucks to suck");
    }
}

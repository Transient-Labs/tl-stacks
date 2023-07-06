// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ITLStacks1155Events} from "tl-stacks/utils/ITLStacks1155Events.sol";

struct Drop {
    uint256 initial_supply;
    uint256 supply;
    uint256 allowance;
    address currency_addr;
    address payout_receiver;
    uint256 start_time;
    uint256 presale_duration;
    uint256 presale_cost;
    bytes32 presale_merkle_root;
    uint256 public_duration;
    uint256 public_cost;
}

interface ITLStacks1155 is ITLStacks1155Events {
    function set_paused(bool paused) external;

    function transfer_ownership(address new_owner) external;

    function configure_drop(
        address nft_addr,
        uint256 token_id,
        uint256 supply,
        uint256 allowance,
        address currency_addr,
        address payout_receiver,
        uint256 start_time,
        uint256 presale_duration,
        uint256 presale_cost,
        bytes32 presale_merkle_root,
        uint256 public_duration,
        uint256 public_cost
    ) external;

    function close_drop(address nft_addr, uint256 token_id) external;

    function update_drop_param(address nft_addr, uint256 token_id, uint256 phase, uint256 param, bytes32 param_value) external;

    function mint(
        address nft_addr,
        uint256 token_id,
        uint256 num_to_mint,
        address receiver,
        bytes32[] calldata proof,
        uint256 allowlist_allocation
    ) external payable;

    function get_drop(address nft_addr, uint256 token_id) external view returns (Drop memory);

    function get_num_minted(address nft_addr, uint256 token_id, address user) external view returns (uint256);

    function get_drop_phase(address nft_addr, uint256 token_id) external view returns (uint256);

    function get_drop_round(address nft_addr, uint256 token_id) external view returns (uint256);

    function paused() external view returns (bool);

    function owner() external view returns (address);
}
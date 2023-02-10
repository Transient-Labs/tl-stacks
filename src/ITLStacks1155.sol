// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import {ITLStacks1155Events} from "tl-stacks/utils/ITLStacks1155Events.sol";

struct Drop {
    uint256 supply;
    int256 decay_rate;
    uint256 allowance;
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

    function configure_drop(
        address _nft_addr,
        uint256 _token_id,
        uint256 _supply,
        int256 _decay_rate,
        uint256 _allowance,
        address _payout_receiver,
        uint256 _start_time,
        uint256 _presale_duration,
        uint256 _presale_cost,
        bytes32 _presale_merkle_root,
        uint256 _public_duration,
        uint256 _public_cost
    ) external;

    function close_drop(address _nft_addr, uint256 _token_id) external;

    function update_drop_param(
        address _nft_addr,
        uint256 _token_id,
        uint256 _phase,
        uint256 _param,
        bytes32 _param_value
    ) external;

    function mint(
        address _nft_addr,
        uint256 _token_id,
        uint256 _num_mint,
        address _receiver,
        bytes32[] calldata _proof,
        uint256 _allowlist_allocation
    ) external payable;

    function get_drop(address _nft_addr, uint256 _token_id)
        external
        view
        returns (Drop memory);

    function get_num_minted(
        address _nft_addr,
        uint256 _token_id,
        address _user
    ) external view returns (uint256);

    function get_drop_phase(address _nft_addr, uint256 _token_id)
        external
        view
        returns (uint256);

    function is_paused() external view returns (bool);

    function owner() external view returns (address);
}

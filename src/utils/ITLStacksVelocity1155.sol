// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Drop {
    uint256 initial_supply;
    uint256 supply;
    uint256 allowance;
    address currency_addr;
    address payout_receiver;
    uint256 start_time;
    uint256 duration;
    uint256 cost;
    int256 decay_rate;
}

interface ITLStacksVelocity1155Events {
    event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

    event Paused(address indexed sender, bool indexed status);

    event DropConfigured(address indexed configurer, address indexed nft_addr, uint256 indexed block_number, uint256 token_id);

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nft_addr,
        uint256 token_id,
        address currency_addr,
        uint256 amount,
        uint256 price
    );

    event DropClosed(address indexed closer, address indexed nft_addr, uint256 indexed token_id);

    event DropUpdated(
        address indexed updater, address indexed nft_addr, uint256 indexed token_id, uint256 dropPhase, uint256 dropParam, bytes32 value
    );
}

interface ITLStacksVelocity1155 is ITLStacksVelocity1155Events {
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
        uint256 duration,
        uint256 cost,
        int256 decay_rate
    ) external;

    function close_drop(address nft_addr, uint256 token_id) external;

    function update_drop_param(address nft_addr, uint256 token_id, uint256 phase, uint256 param, bytes32 param_value) external;

    function mint(
        address nft_addr,
        uint256 token_id,
        uint256 num_to_mint,
        address receiver
    ) external payable;

    function get_drop(address nft_addr, uint256 token_id) external view returns (Drop memory);

    function get_num_minted(address nft_addr, uint256 token_id, address user) external view returns (uint256);

    function get_drop_phase(address nft_addr, uint256 token_id) external view returns (uint256);

    function get_drop_round(address nft_addr, uint256 token_id) external view returns (uint256);

    function paused() external view returns (bool);

    function owner() external view returns (address);
}

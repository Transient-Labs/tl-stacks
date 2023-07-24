// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Drop {
    string base_uri;
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

interface ITLStacksVelocity721Events {
    event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

    event Paused(address indexed sender, bool indexed status);

    event DropConfigured(address indexed configurer, address indexed nft_addr, uint256 indexed block_number);

    event Purchase(
        address indexed buyer,
        address indexed receiver,
        address indexed nft_addr,
        address currency_addr,
        uint256 amount,
        uint256 price
    );

    event DropClosed(address indexed closer, address indexed nft_addr);

    event DropUpdated(
        address indexed updater, address indexed nft_addr, uint256 dropPhase, uint256 dropParam, bytes32 value
    );
}

interface ITLStacksVelocity721 is ITLStacksVelocity721Events {
    function set_paused(bool paused) external;

    function transfer_ownership(address new_owner) external;

    function configure_drop(
        address nft_addr,
        string calldata base_uri,
        uint256 supply,
        uint256 allowance,
        address currency_addr,
        address payout_receiver,
        uint256 start_time,
        uint256 duration,
        uint256 cost,
        int256 decay_rate
    ) external;

    function close_drop(address nft_addr) external;

    function update_drop_param(address nft_addr, uint256 phase, uint256 param, bytes32 param_value) external;

    function mint(
        address nft_addr,
        uint256 num_to_mint,
        address receiver
    ) external payable;

    function get_drop(address nft_addr) external view returns (Drop memory);

    function get_num_minted(address nft_addr, address user) external view returns (uint256);

    function get_drop_phase(address nft_addr) external view returns (uint256);

    function get_drop_round(address nft_addr) external view returns (uint256);

    function paused() external view returns (bool);

    function owner() external view returns (address);
}

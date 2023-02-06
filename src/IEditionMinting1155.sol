// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

interface IEditionMinting1155 {
    enum DropPhase {
        NOT_CONFIGURED,
        BEFORE_SALE,
        PRESALE,
        PUBLIC_SALE,
        ENDED
    }

    enum DropParam {
        MERKLE_ROOT,
        ALLOWANCE,
        COST,
        DURATION,
        PAYOUT_ADDRESS
    }

    struct Drop {
        address nft_addr;
        uint256 token_id;
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

    function set_paused(bool paused) external;

    function configure_drop(
        address nft_addr, 
        uint256 token_id, 
        uint256 supply, 
        int256 decay_rate, 
        uint256 allowance, 
        address payout_receiver, 
        uint256 start_time, 
        uint256 presale_duration, 
        uint256 presale_cost, 
        bytes32 presale_merkle_root, 
        uint256 public_duration, 
        uint256 public_cost
    ) external;
    
    function close_drop(address nft_addr, uint256 token_id) external;

    function update_drop_param(address nft_addr, uint256 token_id, DropPhase phase, DropParam param, bytes32 param_value) external;

    function mint(
        address nft_addr, 
        uint256 token_id, 
        uint256 num_mint, 
        bytes32[] calldata proof,
        uint256 allowlist_allocation
    ) external payable;

    function get_drop(address nft_addr, uint256 token_id) external view returns (Drop memory);

    function get_num_minted(
        address nft_addr, 
        uint256 token_id, 
        address user
    ) external view returns (uint256);

    function get_drop_phase(address nft_addr, uint256 token_id) external view returns (DropPhase);

    function is_paused() external view returns (bool);

    function owner() external view returns (address);
}
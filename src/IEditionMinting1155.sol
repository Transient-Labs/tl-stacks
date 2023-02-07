// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

library DropPhase {
    uint256 constant NOT_CONFIGURED = 1;
    uint256 constant BEFORE_SALE = 2;
    uint256 constant PRESALE = 4;
    uint256 constant PUBLIC_SALE = 8;
    uint256 constant ENDED = 16;
}

library DropParam {
    uint256 constant MERKLE_ROOT = 1;
    uint256 constant ALLOWANCE = 2;
    uint256 constant COST = 4;
    uint256 constant DURATION = 8;
    uint256 constant PAYOUT_ADDRESS = 16;
}

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

interface IEditionMinting1155 {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event DropConfigured(
        address indexed configurer,
        address indexed nftContract,
        uint256 tokenId
    );

    event Purchase(
        address indexed buyer,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        bool isPresale
    );

    event DropClosed(
        address indexed closer,
        address indexed nftContract,
        uint256 tokenId
    );

    event DropUpdated(uint256 dropPhase, uint256 dropParam, bytes32 value);

    event Paused(bool newStatus);

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

    function update_drop_param(
        address nft_addr,
        uint256 token_id,
        uint256 phase,
        uint256 param,
        bytes32 param_value
    ) external;

    function mint(
        address nft_addr,
        uint256 token_id,
        uint256 num_mint,
        bytes32[] calldata proof,
        uint256 allowlist_allocation
    ) external payable;

    function get_drop(address nft_addr, uint256 token_id)
        external
        view
        returns (Drop memory);

    function get_num_minted(
        address nft_addr,
        uint256 token_id,
        address user
    ) external view returns (uint256);

    function get_drop_phase(address nft_addr, uint256 token_id)
        external
        view
        returns (uint256);

    function is_paused() external view returns (bool);

    function owner() external view returns (address);
}

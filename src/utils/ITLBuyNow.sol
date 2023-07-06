// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Sale {
    address seller;
    address payout_receiver;
    address currency_addr;
    uint256 price;
}

interface ITLBuyNowEvents {
    event OwnershipTransferred(address indexed previous_owner, address indexed new_owner);

    event Paused(address indexed sender, bool indexed status);

    event RoyaltyEngineUpdated(address indexed previous_engine_addr, address indexed new_engine_addr);

    event SaleConfigured(address indexed sender, address indexed nft_addr, uint256 indexed token_id, Sale sale);

    event SalePriceUpdated(address indexed sender, address indexed nft_addr, uint256 indexed token_id, Sale sale);

    event SaleCanceled(address indexed sender, address indexed nft_addr, uint256 indexed token_id);

    event SaleFulfilled(address indexed buyer, address indexed nft_addr, uint256 indexed token_id, Sale sale);

}

interface ITLBuyNow is ITLBuyNowEvents {

    function set_paused(bool paused) external;

    function transfer_ownership(address new_owner) external;

    function update_royalty_engine(address engine_addr) external;

    function configure_sale(address nft_addr, uint256 token_id, address payout_receiver, address currency_addr, uint256 price) external;

    function update_sale_price(address nft_addr, uint256 token_id, address currency_addr, uint256 price) external;

    function cancel_sale(address nft_addr, uint256 token_id) external;

    function buy(address nft_addr, uint256 token_id) external payable;

    function get_sale(address nft_addr, uint256 token_id) external view returns (Sale memory);
}
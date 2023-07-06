# @version 0.3.9

"""
@title TLBuyNow
@notice Buy now sales contract for minted ERC-721 tokens
@author transientlabs.xyz
@license MIT
@custom:version 2.0.0
"""

###########################################################################
#                              Interfaces
###########################################################################

interface IERC721:
    def getApproved(token_id: uint256) -> address: view
    def isApprovedForAll(owner: address, operator: address) -> bool: view
    def transferFrom(from_: address, to: address, token_id: uint256): payable
    def ownerOf(token_id: uint256) -> address: view

interface IERC20:
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view
    def transferFrom(from_: address, to: address, amount: uint256) -> bool: payable

interface RoyaltyEngine:
    def getRoyalty(nft_addr: address, token_id: uint256, value_: uint256) -> (DynArray[address, 100], DynArray[uint256, 100]): nonpayable


###########################################################################
#                              Constants
###########################################################################

BASIS: public(constant(uint256)) = 10_000

###########################################################################
#                                Structs
###########################################################################

struct Sale:
    seller: address
    payout_receiver: address
    currency_addr: address
    price: uint256

###########################################################################
#                                Events
###########################################################################

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event Paused:
    sender: indexed(address)
    status: indexed(bool)

event RoyaltyEngineUpdated:
    previous_engine_addr: indexed(address)
    new_engine_addr: indexed(address)

event SaleConfigured:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

event SalePriceUpdated:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

event SaleCanceled:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)

event SaleFulfilled:
    buyer: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

###########################################################################
#                            State Variables
###########################################################################

owner: public(address)
paused: public(bool)
royalty_engine: public(address)
_sales: HashMap[address, HashMap[uint256, Sale]] # nft_addr -> token_id -> sale

###########################################################################
#                             Constructor
###########################################################################

@external
def __init__(init_owner: address, engine_addr: address):
    self._transfer_ownership(init_owner)
    self._update_royalty_engine(engine_addr)

###########################################################################
#                         Owner Write Functions
###########################################################################

@external
def set_paused(paused: bool):
    """
    @notice Function to pause or unpause the contract
    @dev Requires msg.sender to be the contract owner
    @param paused A boolean with the pause state to set
    """
    assert msg.sender == self.owner, "caller not owner"
    self.paused = paused
    log Paused(msg.sender, paused)

@external
def transfer_ownership(new_owner: address):
    """
    @notice Function to transfer ownership of the contract
    @dev Requires msg.sender to be the contract owner
    @param new_owner The address to transfer ownership to
    """
    assert msg.sender == self.owner, "caller not owner"
    self._transfer_ownership(new_owner)

@external
def update_royalty_engine(engine_addr: address):
    """
    @notice Function to update the royalty engine address
    @dev Requires msg.sender to be the contract owner
    @param engine_addr The new royalty engine address
    """
    assert msg.sender == self.owner, "caller not owner"
    self._update_royalty_engine(engine_addr)

@internal
def _transfer_ownership(new_owner: address):
    """
    @dev Logs an `OwnershipTransferred` event
    @param new_owner The address to transfer ownership to
    """
    prev_owner: address = self.owner
    self.owner = new_owner
    log OwnershipTransferred(prev_owner, new_owner)

@internal
def _update_royalty_engine(engine_addr: address):
    """
    @dev Logs an `RoyaltyEngineUpdated` event
    @param engine_addr The new royalty engine address
    """
    prev_engine_addr: address = self.royalty_engine
    self.royalty_engine = engine_addr
    log RoyaltyEngineUpdated(prev_engine_addr, engine_addr)

###########################################################################
#                        Sales Configuration Functions
###########################################################################

@external
def configure_sale(nft_addr: address, token_id: uint256, payout_receiver: address, currency_addr: address, price: uint256):
    """
    @notice Function to configure a sale
    @dev Not allowed if the contract is paused
    @dev msg.sender must be the token owner
    @dev msg.sender must have this contract approved for the token
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param payout_receiver The address to which funds are sent from the sale, after creator royalties taken into account
    @param currency_addr The currency to use. Use the null address to specify ETH. Otherwise will assume it is an ERC-20 token
    @param price The price of the token
    """
    assert not self.paused, "contract is paused"

    nft_contract: IERC721 = IERC721(nft_addr)
    assert nft_contract.ownerOf(token_id) == msg.sender, "caller is not the token owner"
    assert nft_contract.getApproved(token_id) == self or nft_contract.isApprovedForAll(msg.sender, self), "caller does not have the contract approved for the token"

    sale: Sale = Sale({
        seller: msg.sender,
        payout_receiver: payout_receiver,
        currency_addr: currency_addr,
        price: price
    })

    self._sales[nft_addr][token_id] = sale

    log SaleConfigured(msg.sender, nft_addr, token_id, sale)

@external
def update_sale_price(nft_addr: address, token_id: uint256, currency_addr: address, price: uint256):
    """
    @notice Function to update the sale price of the drop
    @dev Not allowed if the contract is paused
    @dev Requires that msg.sender is the nft seller
    @dev Requires the sale to be set
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param currency_addr The currency to use. Use the null address to specify ETH. Otherwise will assume it is an ERC-20 token
    @param price The price of the token
    """
    assert not self.paused, "contract is paused"

    sale: Sale = self._sales[nft_addr][token_id]
    assert msg.sender == sale.seller, "caller is not the token owner"

    sale.currency_addr = currency_addr
    sale.price = price

    self._sales[nft_addr][token_id] = sale

    log SalePriceUpdated(msg.sender, nft_addr, token_id, sale)
    
@external
def cancel_sale(nft_addr: address, token_id: uint256):
    """
    @notice Function to cancel the sale
    @dev Requires that msg.sender is the nft seller
    @dev Requires the sale to be set
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    sale: Sale = self._sales[nft_addr][token_id]
    assert msg.sender == sale.seller, "caller is not the token owner"

    self._sales[nft_addr][token_id] = empty(Sale)

    log SaleCanceled(msg.sender, nft_addr, token_id)

###########################################################################
#                                Buy Now
###########################################################################

@external
@payable
@nonreentrant("buy different")
def buy(nft_addr: address, token_id: uint256):
    """
    @notice Function to buy a token for the listed price
    @dev Not allowed if the contract is paused
    @dev Checks if the sale is active
    @dev Transfers the NFT to the buyer, transfers royalty fees, and transfers remaining funds to the seller
    @dev If fund transfers revert, the entire transaction reverts. This is on the seller/royalty setup by the artist
         Since no funds or NFT is escrowed, there is no risk of funds getting stuck in the contract
    @dev Checks if either the eth sent with the tx is enough or if enough approval/balance for ERC-20 tokens is given.
         Reverts if either case is not met, as needed.
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    assert not self.paused, "contract is paused"

    sale: Sale = self._sales[nft_addr][token_id]
    assert sale.seller != empty(address), "sale not active"

    royalty_info: (DynArray[address, 100], DynArray[uint256, 100]) = RoyaltyEngine(self.royalty_engine).getRoyalty(nft_addr, token_id, BASIS)
    assert len(royalty_info[0]) == len(royalty_info[1]), "invalid royalty info"

    self._sales[nft_addr][token_id] = empty(Sale)
    
    self._transfer_funds(sale.currency_addr, sale.price, msg.sender, sale.payout_receiver, royalty_info[0], royalty_info[1])

    IERC721(nft_addr).transferFrom(sale.seller, msg.sender, token_id)

    log SaleFulfilled(msg.sender, nft_addr, token_id, sale)


@internal
@payable
def _transfer_funds(currency_addr: address, price: uint256, from_: address, to: address, royalty_receivers: DynArray[address, 100], royalty_fees: DynArray[uint256, 100]):
    """
    @notice Function to transfer funds
    @dev Verifies that either enough ether is attached or that the contract can transfer enough ERC-20 tokens from `from_`
    @param currency_addr The address for the currency. The null address means ETH, otherwise assuming ERC-20 tokens
    @param price The price of the sale
    @param from_ The address from which funds are taken
    @param to The address to which remaining sales funds are sent
    @param royalty_receivers The addresses to which some royalties should be paid
    @param royalty_fees The percentages, out of `BASIS`, to pay to the `royalty_recipients`
    """
    if currency_addr == empty(address):
        assert msg.value >= price, "insufficient funds"

        remaining_sale: uint256 = price
        for i in range(0, 100):
            if i >= len(royalty_receivers):
                break
            fee: uint256 = price / BASIS * royalty_fees[i]
            self._send_eth(royalty_receivers[i], fee)
            remaining_sale -= fee

        self._send_eth(to, remaining_sale)

        if msg.value > price:
            refund: uint256 = msg.value - price
            self._send_eth(from_, refund)
    else:
        token: IERC20 = IERC20(currency_addr)
        assert token.allowance(from_, self) >= price and token.balanceOf(from_) >= price, "insufficient funds"
        
        remaining_sale: uint256 = price
        for i in range(0, 100):
            if i >= len(royalty_receivers):
                break
            fee: uint256 = price / BASIS * royalty_fees[i]
            self._transfer_erc20(currency_addr, from_, royalty_receivers[i], fee)
            remaining_sale -= fee

        self._transfer_erc20(currency_addr, from_, to, remaining_sale)

        if msg.value > 0:
            self._send_eth(from_, msg.value)

@internal
@payable
def _send_eth(recipient: address, eth_amount: uint256):
    """
    @notice Runction to send eth, forwarding all gas
    @dev Returns if eth_amount is zero
    @dev Reverts on failure
    @param recipient The address to receive ETH
    @param eth_amount The amount of ETH (in wei) to send
    """
    if eth_amount == 0:
        return
    raw_call(
        recipient,
        b"",
        max_outsize=0,
        value=eth_amount,
        revert_on_failure=True
    )   

@internal
@payable
def _transfer_erc20(erc20_addr: address, from_: address, to: address, num_tokens: uint256):
    """
    @notice Function to transfer ERC-20 tokens to a recipient, verifying that it was successful
    @dev Returns if num_tokens is zero
    @dev Reverts on failure
    @dev If the `from_` is the same as `to`, then there is no need to transfer the tokens.
    @param erc20_addr The address for erc20 token contract
    @param from_ The address from which the erc20 tokens will be taken
    @param to The recipient for the erc20 tokens
    @param num_tokens The number of tokens to transfer
    """
    if num_tokens == 0 or from_ == to:
        return
    assert IERC20(erc20_addr).transferFrom(from_, to, num_tokens, default_return_value=True), "ERC20 token transfer not successful"

###########################################################################
#                           External Read Functions
###########################################################################

@external
@view
def get_sale(nft_addr: address, token_id: uint256) -> Sale:
    """
    @notice Function to get sale for an NFT
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    return self._sales[nft_addr][token_id]
# @version 0.3.9

"""
@title TLReserveAuction
@notice Reserve auction contract for minted ERC-721 tokens
@author transientlabs.xyz
@license MIT
@custom:version 2.0.0
"""

###########################################################################
#                              Interfaces
###########################################################################

interface IERC721:
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
EXTENSION_TIME: public(constant(uint256)) = 900 # 15 minutes

###########################################################################
#                                Structs
###########################################################################

struct Auction:
    seller: address
    payout_receiver: address
    currency_addr: address
    reserve_price: uint256
    min_bid_increase: uint256
    duration: uint256
    start_time: uint256

struct AuctionBid:
    bidder: address
    currency_addr: address
    amount: uint256

###########################################################################
#                                Events
###########################################################################

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event Paused:
    sender: indexed(address)
    status: indexed(bool)

event AuctionConfigured:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)

event AuctionStartTimeUpdated:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    auction: Auction

event AuctionReservePriceUpdated:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    auction: Auction

event AuctionCanceled:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)

event AuctionSettled:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    auction: Auction

event Bid:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    auction: Auction

###########################################################################
#                            State Variables
###########################################################################

# nft_addr -> token_id -> auction
_auctions: HashMap[address, HashMap[uint256, Auction]]

# nft_addr -> token_id -> bid
_bids: HashMap[address, HashMap[uint256, AuctionBid]]

owner: public(address)
paused: public(bool)

###########################################################################
#                              Modifiers
###########################################################################

# View used as a modifier to check if the contract is paused
@internal
@view
def mod_if_not_paused():
    if self.paused:
        raise "contract is paused"

# View used as a modifier to check if msg.sender is contract owner
@internal
@view
def mod_only_owner():
    if msg.sender != self.owner:
        raise "only owner"

# View used as modifier to check if an auction is in the derired state.
@internal
@view
def mod_auction_exists(_nft_addr: address, _token_id: uint256, _should_exist: bool):
    if (self._auctions[_nft_addr][_token_id].seller != empty(address)) != _should_exist:
        raise "auction is in undesired state"

# View used as modifier to check if sender is the token owner.
@internal
@view
def mod_only_token_owner(_nft_addr: address, _token_id: uint256):
    if IERC721(_nft_addr).ownerOf(_token_id) != msg.sender:
        raise "only token owner"

# View used as modifier to check if address has approved this contract for all.
@internal
@view
def mod_is_auction_approved_for_all(_nft_addr: address, _owner: address):
    if not IERC721(_nft_addr).isApprovedForAll(_owner, self):
        raise "auction not approved for all"

###########################################################################
#                               Constructor
###########################################################################

# Constructor of contract setting owner to {_owner}.
@external
def __init__(_owner: address):
    self.owner = _owner
    self.paused = False

###########################################################################
#                             Admin Functions
###########################################################################

# Sets the contract to be {_paused}.
# Only callable by the contract owner
@external
def set_contract_paused(_paused: bool):
    self.mod_only_owner()
    self.paused = _paused
    log Paused(msg.sender, _paused)

# Transfers contract ownership to {_new_owner}.
# Only callable by the contract owner
@external
def transfer_ownership(_new_owner: address):
    self.mod_only_owner()
    old_owner: address = self.owner
    self.owner = _new_owner
    log OwnershipTransferred(old_owner, _new_owner)

###########################################################################
#                            Write Functions
###########################################################################

# Configures an auction for a given nft
# Ensures:
#   - the sender is the owner
#   - an auction doesnt already exist
#   - auction house is approved for all for the sender
@external
def configure_auction(
    _nft_addr: address,
    _token_id: uint256,
    _payout_receiver: address,
    _currency_addr: address,
    _reserve_price: uint256,
    _min_bid_increase: uint256,
    _duration: uint256,
    _start_time: uint256
):
    self.mod_auction_exists(_nft_addr, _token_id, False)
    self.mod_only_token_owner(_nft_addr, _token_id)
    self.mod_is_auction_approved_for_all(_nft_addr, msg.sender)

    self._auctions[_nft_addr][_token_id] = Auction({
        seller: msg.sender,
        payout_receiver: _payout_receiver,
        currency_addr: _currency_addr,
        reserve_price: _reserve_price,
        min_bid_increase: _min_bid_increase,
        duration: _duration,
        start_time: _start_time
    })

    log AuctionConfigured(msg.sender, _nft_addr, _token_id)

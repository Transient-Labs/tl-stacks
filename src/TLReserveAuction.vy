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
BID_BUFFER_SEC: public(constant(uint256)) = 900 # 15 minutes

###########################################################################
#                                Structs
###########################################################################

struct Auction:
    seller: address
    payout_receiver: address
    highest_bidder: address
    currency_addr: address
    royalty_receiver: address
    royalty_fee: uint256
    reserve_price: uint256
    highest_bid: uint256
    min_bid_increase: uint256
    duration: uint256
    start_time: uint256
    first_bid_time: uint256

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
    auction: Auction

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

owner: public(address)
paused: public(bool)
_auctions: HashMap[address, HashMap[uint256, Auction]] # nft_addr -> token_id -> auction
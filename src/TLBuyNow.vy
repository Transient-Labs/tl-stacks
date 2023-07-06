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
    royalty_receiver: address
    royalty_fee: uint256
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

event SaleConfigured:
    seller: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

event SaleCanceled:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)

event Sale:
    buyer: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

###########################################################################
#                            State Variables
###########################################################################

owner: public(address)
paused: public(bool)
_sales: HashMap[address, HashMap[uint256, Sale]] # nft_addr -> token_id -> sale
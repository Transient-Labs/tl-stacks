# @version 0.3.9

"""
@title TLAuctionHouse
@notice TL Auction House contract for minted ERC-721 tokens
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
    def transfer(to: address, amount: uint256) -> bool: payable
    def transferFrom(from_: address, to: address, amount: uint256) -> bool: payable

###########################################################################
#                              Constants
###########################################################################

VERSION: public(constant(String[5])) = "1.0.0"
EXTENSION_TIME: public(constant(uint256)) = 900 # 15 minutes
BASIS: public(constant(uint256)) = 10_000

###########################################################################
#                                Structs
###########################################################################

struct Auction:
    seller: address
    payout_receiver: address
    currency_addr: address
    highest_bidder: address
    highest_bid: uint256
    reserve_price: uint256
    min_bid_increase: uint256
    bid_open_time: uint256
    duration: uint256
    start_time: uint256
    merkle_root: bytes32

struct Sale:
    seller: address
    payout_receiver: address
    currency_addr: address
    price: uint256
    merkle_root: bytes32

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

event AuctionConfigured:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    auction: Auction

event AuctionUpdated:
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

event SaleConfigured:
    sender: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    sale: Sale

event SaleUpdated:
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
    recipient: address
    sale: Sale

event EthEscrowed:
    recipient: indexed(address)
    amount: indexed(uint256)

###########################################################################
#                            State Variables
###########################################################################

owner: public(address)
paused: public(bool)
royalty_engine: public(address)
_auctions: HashMap[address, HashMap[uint256, Auction]] # nft_addr -> token_id -> auction
_sales: HashMap[address, HashMap[uint256, Sale]] # nft_addr -> token_id -> sale
_eth_escrowed: HashMap[address, uint256] # address -> eth owed

###########################################################################
#                               Constructor
###########################################################################

@external
@payable
def __init__(init_owner: address, engine_addr: address):
    self._transfer_ownership(init_owner)
    self._update_royalty_engine(engine_addr)

###########################################################################
#                              Internal Checkers
###########################################################################

@internal
@view
def _if_not_paused():
    """
    @notice Internal function to verify if the contract is paused
    @dev Reverts if paused
    """
    if self.paused:
        raise "contract is paused"

@internal
@view
def _only_owner():
    """
    @notice Internal function to verify if the msg sender is the contract owner
    @dev Reverts if not the case
    """
    if msg.sender != self.owner:
        raise "caller is not the owner"

@internal
@view
def _auction_exists(auction: Auction):
    """
    @notice Internal function to verify if the auction exists
    @dev Reverts if the auction does not exist
    """
    if auction.seller == empty(address):
        raise "auction not configured"

@internal
@view
def _auction_does_not_exist(auction: Auction):
    """
    @notice Internal function to verify if the auction doesn't exist
    @dev Reverts if the auction exists
    """
    if auction.seller != empty(address):
        raise "auction already configured"

@internal
@view
def _auction_not_started(auction: Auction):
    """
    @notice Internal function to verify that the auction hasn't been started
    @dev Reverts if the auction has been started
    """
    if auction.start_time != 0:
        raise "auction already started"

@internal
@view
def _only_auction_seller(auction: Auction):
    """
    @notice Internal function to verify if the msg sender is the auction seller
    @dev Reverts if the caller is not the seller
    """
    if auction.seller != msg.sender:
        raise "caller not auction seller"

@internal
@view
def _not_auction_seller(auction: Auction):
    """
    @notice Internal function to verify that the msg sender is NOT the auction seller
    @dev Reverts if the caller is the seller
    """
    if auction.seller == msg.sender:
        raise "caller is auction seller"

@internal
@view
def _sale_exists(sale: Sale):
    """
    @notice Internal function to verify if the sale exists
    @dev Reverts if the sale does not exist
    """
    if sale.seller == empty(address):
        raise "sale not configured"

@internal
@view
def _sale_does_not_exist(sale: Sale):
    """
    @notice Internal function to verify if the sale doesn't exist
    @dev Reverts if the sale exists
    """
    if sale.seller != empty(address):
        raise "sale already configured"

@internal
@view
def _only_sale_seller(sale: Sale):
    """
    @notice Internal function to verify if the msg sender is the sale seller
    @dev Reverts if the caller is not the seller
    """
    if sale.seller != msg.sender:
        raise "caller not sale seller"

@internal
@view
def _not_sale_seller(sale: Sale):
    """
    @notice Internal function to verify if the msg sender is NOT the sale seller
    @dev Reverts if the caller is the seller
    """
    if sale.seller == msg.sender:
        raise "caller is sale seller"

@internal
@view
def _only_token_owner(nft_contract: IERC721, token_id: uint256):
    """
    @notice Internal function to verify that the msg sender is the token owner
    @dev Reverts if they are not the token owner
    """
    if nft_contract.ownerOf(token_id) != msg.sender:
        raise "only token owner"

@internal
@view
def _is_auction_house_approved_for_all(nft_contract: IERC721):
    """
    @notice Internal function to verify that the auction house is approved as an operator for the token
    @dev Reverts if not approved for all or approved for the token
    """
    if not nft_contract.isApprovedForAll(msg.sender, self):
        raise "auction not approved for the token"

@internal
@payable
def _has_sufficient_funds(currency_addr: address, amount: uint256, from_: address):
    """
    @notice Internal function to verify that the msg sender has enough funds for the purchase/bid
    @dev Reverts if not
    """
    if currency_addr == empty(address):
        if msg.value < amount:
            raise "insufficient eth funds"
    else:
        token: IERC20 = IERC20(currency_addr)
        if token.allowance(from_, self) < amount or token.balanceOf(from_) < amount:
            raise "insufficient erc20 funds"

###########################################################################
#                              Internal Helpers
###########################################################################

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

@internal
def _get_royalty_info(nft_addr: address, token_id: uint256, amount: uint256) -> (DynArray[address, max_value(uint8)], DynArray[uint256, max_value(uint8)]):
    """
    @notice Function to get royalty info
    @dev If the lookup reverts, as is possible in the Royalty Registry, return back empty arrays
    @dev checks if the royalty engine is a contract and if not, the raw_call technically doesn't revert,
         so need to verify if the address is a contract.
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @return DynArray[address, 100] The list of addresses to send payment to
    @return DynArray[uint256, 100] The amount of currency to transfer to each address in the first index of the output tuple
    """
    if self.royalty_engine.is_contract:
        success: bool = False
        data: Bytes[16448] = b""
        success, data = raw_call(
            self.royalty_engine,
            _abi_encode(nft_addr, token_id, amount, method_id=method_id("getRoyalty(address,uint256,uint256)")),
            max_outsize=16448,
            revert_on_failure=False
        )
        if not success:
            return (empty(DynArray[address, max_value(uint8)]), empty(DynArray[uint256, max_value(uint8)]))

        recipients: DynArray[address, max_value(uint8)] = empty(DynArray[address, max_value(uint8)])
        fees: DynArray[uint256, max_value(uint8)] = empty(DynArray[uint256, max_value(uint8)])
        recipients, fees = _abi_decode(data, (DynArray[address, max_value(uint8)], DynArray[uint256, max_value(uint8)]))
       
        if len(recipients) != len(fees):
            raise "invalid royalty info"

        total: uint256 = 0
        for fee in fees:
            total += fee

        if total > amount:
            raise "invalid royalty fee sum"

        return (recipients, fees)
    else:
        return (empty(DynArray[address, max_value(uint8)]), empty(DynArray[uint256, max_value(uint8)]))

@internal
@payable
def _send_eth(recipient: address, amount: uint256):
    """
    @notice Runction to send eth, forwarding all gas
    @dev Returns if eth_amount is zero
    @dev Stores eth in the contract on case of revert
    @param recipient The address to receive ETH
    @param amount The amount of ETH (in wei) to send
    """
    if amount == 0:
        return
    success: bool = False
    data: Bytes[1] = empty(Bytes[1])
    success, data = raw_call(
        recipient,
        b"",
        max_outsize=1,
        value=amount,
        revert_on_failure=False
    )

    if not success:
        self._eth_escrowed[recipient] += amount
        log EthEscrowed(recipient, amount)

@internal
@payable
def _transfer_erc20_from_address(erc20_addr: address, from_: address, to: address, num_tokens: uint256):
    """
    @notice Function to transfer ERC-20 tokens from a sender to a recipient, verifying that it was successful
    @dev Returns if num_tokens is zero
    @dev Reverts on failure
    @dev If the `from_` is the same as `to`, then there is no need to transfer the tokens
    @param erc20_addr The address for erc20 token contract
    @param from_ The address from which the erc20 tokens will be taken
    @param to The recipient for the erc20 tokens
    @param num_tokens The number of tokens to transfer
    """
    if num_tokens == 0:
        return
    erc20: IERC20 = IERC20(erc20_addr)
    prev_balance: uint256 = erc20.balanceOf(to)
    if not IERC20(erc20_addr).transferFrom(from_, to, num_tokens, default_return_value=True):
        raise "ERC20 token transfer from address not successful"

    if erc20.balanceOf(to) - prev_balance != num_tokens:
        raise "ERC20 token transfer did not transfer the expected amount"

@internal
@payable
def _transfer_erc20_from_contract(erc20_addr: address, to: address, num_tokens: uint256):
    """
    @notice Function to transfer ERC-20 tokens from the contract to a recipient, verifying that it was successful
    @dev Returns if num_tokens is zero
    @dev Reverts on failure
    @dev If the `from_` is the same as `to`, then there is no need to transfer the tokens
    @param erc20_addr The address for erc20 token contract
    @param from_ The address from which the erc20 tokens will be taken
    @param to The recipient for the erc20 tokens
    @param num_tokens The number of tokens to transfer
    """
    if num_tokens == 0:
        return

    if not IERC20(erc20_addr).transfer(to, num_tokens, default_return_value=True):
        raise "ERC20 token transfer from contract not successful"

@internal
@pure
def _verify_proof(proof: DynArray[bytes32, max_value(uint16)], root: bytes32, leaf: bytes32):
    """
    @notice function to verify a merkle proof
    @dev each pair of leaves and each pair of hashes in the tree are assumed to be sorted.
    @param proof The bytes32 array of sibling hashes that lead from the `leaf` to the `root`
    @param root The merkle root to check against
    @param leaf The leaf to check
    @return bool The verification if the proof is valid for the leaf or not 
    """
    computed_hash: bytes32 = leaf
    for p in proof:
        if convert(computed_hash, uint256) < convert(p, uint256):
            computed_hash = keccak256(concat(computed_hash, p))  
        else: 
            computed_hash = keccak256(concat(p, computed_hash))
    if computed_hash != root:
        raise "invalid merkle proof"

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
    self._only_owner()
    self.paused = paused
    log Paused(msg.sender, paused)

@external
def transfer_ownership(new_owner: address):
    """
    @notice Function to transfer ownership of the contract
    @dev Requires msg.sender to be the contract owner
    @param new_owner The address to transfer ownership to
    """
    self._only_owner()
    self._transfer_ownership(new_owner)

@external
def update_royalty_engine(engine_addr: address):
    """
    @notice Function to update the royalty engine address
    @dev Requires msg.sender to be the contract owner
    @param engine_addr The new royalty engine address
    """
    self._only_owner()
    self._update_royalty_engine(engine_addr)

###########################################################################
#                    Auction Configuration Functions
###########################################################################

@external
def configure_auction(
    nft_addr: address,
    token_id: uint256,
    payout_receiver: address,
    currency_addr: address,
    reserve_price: uint256,
    min_bid_increase: uint256,
    bid_open_time: uint256,
    duration: uint256,
    merkle_root: bytes32
):
    """
    @notice function to configure an auction for a token
    @dev Not allowed if the contract is paused
    @dev msg.sender must be the token owner
    @dev msg.sender must have this contract approved for the token
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param payout_receiver The address to which funds are sent from the sale, after creator royalties taken into account
    @param currency_addr The currency to use. Use the null address to specify ETH. Otherwise will assume it is an ERC-20 token
    @param reserve_price The reserve price of the auction
    @param min_bid_increase The minimum bid increase on a basis scale (see `BASIS`)
    @param bid_open_time The timestamp at which bidding opens
    @param duration The duration that the reserve auction should last once started
    @param merkle_root The merkle root for making the sale private. An empty merkle root means it's open to the public
    """
    self._if_not_paused()
    self._auction_does_not_exist(self._auctions[nft_addr][token_id])
    nft_contract: IERC721 = IERC721(nft_addr)
    self._only_token_owner(nft_contract, token_id)
    self._is_auction_house_approved_for_all(nft_contract)

    auction: Auction = Auction({
        seller: msg.sender,
        payout_receiver: payout_receiver,
        currency_addr: currency_addr,
        highest_bidder: empty(address),
        highest_bid: 0,
        reserve_price: reserve_price,
        min_bid_increase: min_bid_increase,
        bid_open_time: bid_open_time,
        duration: duration,
        start_time: 0,
        merkle_root: merkle_root
    })
    self._auctions[nft_addr][token_id] = auction

    log AuctionConfigured(msg.sender, nft_addr, token_id, auction)

@external
def update_auction_reserve_price(nft_addr: address, token_id: uint256, currency_addr: address, reserve_price: uint256):
    """
    @notice Function to update an auction's reserve price
    @dev Not allowed if the contract is paused
    @dev Requires that msg.sender is the nft seller
    @dev Requires the auction to be set
    @dev Requires that the auction has not been started
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param currency_addr The currency to use. Use the null address to specify ETH. Otherwise will assume it is an ERC-20 token
    @param reserve_price The new reserve price of the auction
    """
    self._if_not_paused()
    auction: Auction = self._auctions[nft_addr][token_id]
    self._only_auction_seller(auction)
    self._auction_not_started(auction)

    auction.currency_addr = currency_addr
    auction.reserve_price = reserve_price
    self._auctions[nft_addr][token_id] = auction

    log AuctionUpdated(msg.sender, nft_addr, token_id, auction)

@external
def update_auction_merkle_root(nft_addr: address, token_id: uint256, merkle_root: bytes32):
    """
    @notice Function to update the auction merkle root
    @dev Not allowed if the contract is paused
    @dev Requires that msg.sender is the nft seller
    @dev Requires the auction to be set
    @dev Requires that the auction hasn't been started
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param merkle_root The new merkle root for the sale
    """
    self._if_not_paused()
    auction: Auction = self._auctions[nft_addr][token_id]
    self._only_auction_seller(auction)
    self._auction_not_started(auction)

    auction.merkle_root = merkle_root
    self._auctions[nft_addr][token_id] = auction

    log AuctionUpdated(msg.sender, nft_addr, token_id, auction)

@external
def update_auction_duration(nft_addr: address, token_id: uint256, duration: uint256):
    """
    @notice Function to update the duration of the auction
    @dev Not allowed if the contract is paused
    @dev Requires that msg.sender is the nft seller
    @dev Requires the auction to be set
    @dev Requires that the auction hasn't been started
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param duration The new merkle root for the sale
    """
    self._if_not_paused()
    auction: Auction = self._auctions[nft_addr][token_id]
    self._only_auction_seller(auction)
    self._auction_not_started(auction)

    auction.duration = duration
    self._auctions[nft_addr][token_id] = auction

    log AuctionUpdated(msg.sender, nft_addr, token_id, auction)

@external
def cancel_auction(nft_addr: address, token_id: uint256):
    """
    @notice Function to cancel an auction
    @dev Requires that msg.sender is the nft seller
    @dev Requires the auction to be set
    @dev Requires that the auction hasn't been started
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    auction: Auction = self._auctions[nft_addr][token_id]
    self._only_auction_seller(auction)
    self._auction_not_started(auction)

    self._auctions[nft_addr][token_id] = empty(Auction)

    log AuctionCanceled(msg.sender, nft_addr, token_id)

###########################################################################
#                             Auction Functions
###########################################################################

@external
@payable
@nonreentrant("lock")
def bid(nft_addr: address, token_id: uint256, bidder: address, amount: uint256, proof: DynArray[bytes32, max_value(uint16)]):
    """
    @notice Function to bid on an auction
    @dev Not allowed if the contract is paused 
    @dev Requires the auction to be set
    @dev Reverts if the msg sender is the auction seller
    @dev Not allowed to bid prior to the bid start time or after the duration is complete
    @dev Requires that the amount to bid is greater than or equal to the highest bid plus the min bid increase
    @dev If the auction isn't started, the amount to bid must be greater than or equal to the reserve price and the auction is started
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param bidder The address bidding, even if not the same as the msg sender, but the msg sender still pays all fees
    @param proof The merkle proof for verifying the bidder is allowed to participate in a private auction
    """
    # check pre-conditions
    self._if_not_paused()
    auction: Auction = self._auctions[nft_addr][token_id]
    self._auction_exists(auction)
    self._not_auction_seller(auction)

    # check if allowed to bid
    if block.timestamp < auction.bid_open_time:
        raise "bidding not allowed"

    # check if private sale
    if auction.merkle_root != empty(bytes32):
        leaf: bytes32 = keccak256(convert(bidder, bytes32))
        self._verify_proof(proof, auction.merkle_root, leaf)

    if auction.start_time == 0:
        # check bid amount
        if amount < auction.reserve_price:
            raise "bid does not meet reserve price"
        
        # check for sufficient funds
        self._has_sufficient_funds(auction.currency_addr, amount, msg.sender)

        # clear sale
        self._sales[nft_addr][token_id] = empty(Sale)

        # start sale
        auction.start_time = block.timestamp

        # set highest bidder & bid
        auction.highest_bidder = bidder
        auction.highest_bid = amount

        # transfer funds
        if auction.currency_addr == empty(address):
            # eth is already in the contract, just need to refund potentially
            refund: uint256 = msg.value - amount
            if refund > 0:
                self._send_eth(msg.sender, refund)
        else:
            # need to transfer erc20 and refund eth potentially
            self._transfer_erc20_from_address(auction.currency_addr, msg.sender, self, amount)
            if msg.value > 0:
                self._send_eth(msg.sender, msg.value)

        # escrow NFT
        IERC721(nft_addr).transferFrom(auction.seller, self, token_id)

    else:
        # check if auction is ended
        if block.timestamp > auction.start_time + auction.duration:
            raise "auction ended"

        # check bid amount is greater than or equal to 
        if amount < auction.highest_bid * (BASIS + auction.min_bid_increase) / BASIS:
            raise "bid too low"

        # check for sufficient funds
        self._has_sufficient_funds(auction.currency_addr, amount, msg.sender)

        # if bid is within the extension time, extend the auction
        time_remaining: uint256 = auction.start_time + auction.duration - block.timestamp 
        if time_remaining < EXTENSION_TIME:
            auction.duration += EXTENSION_TIME - time_remaining
        
        # set highest bidder & bid
        prev_highest_bidder: address = auction.highest_bidder
        prev_highest_bid: uint256 = auction.highest_bid
        auction.highest_bidder = bidder
        auction.highest_bid = amount

        # transfer funds
        if auction.currency_addr == empty(address):
            # refund previous highest bidder
            self._send_eth(prev_highest_bidder, prev_highest_bid)
            # new eth bid is already in the contract, just need to refund sender potentially
            refund: uint256 = msg.value - amount
            if refund > 0:
                self._send_eth(msg.sender, refund)
        else:
            # refund previous highest bidder
            self._transfer_erc20_from_contract(auction.currency_addr, prev_highest_bidder, prev_highest_bid)
            # need to transfer erc20 and refund eth potentially
            self._transfer_erc20_from_address(auction.currency_addr, msg.sender, self, amount)
            if msg.value > 0:
                self._send_eth(msg.sender, msg.value)

    # save auction
    self._auctions[nft_addr][token_id] = auction

    log Bid(msg.sender, nft_addr, token_id, auction)

@external
@payable
@nonreentrant("lock")
def settle_auction(nft_addr: address, token_id: uint256):
    """
    @notice Function to settle the auction
    @dev Anyone can call this function but funds and NFT transfer are not affected by this
    @dev Requires the auction to exist
    @dev Requires that the auction is ended
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    # check pre-conditions
    auction: Auction = self._auctions[nft_addr][token_id]
    if auction.start_time == 0:
        raise "auction not started"
    if block.timestamp < auction.start_time + auction.duration:
        raise "auction still ongoing"

    # clear auction
    self._auctions[nft_addr][token_id] = empty(Auction)

    # make external call to get and check royalty config
    royalty_recipients: DynArray[address, max_value(uint8)] = empty(DynArray[address, max_value(uint8)])
    royalty_fees: DynArray[uint256, max_value(uint8)] = empty(DynArray[uint256, max_value(uint8)])
    royalty_recipients, royalty_fees = self._get_royalty_info(nft_addr, token_id, auction.highest_bid)
    
    # pay royalties
    remaining_sale: uint256 = auction.highest_bid
    for i in range(0, 255):
        if i == len(royalty_recipients):
            break
        if auction.currency_addr == empty(address):
            self._send_eth(royalty_recipients[i], royalty_fees[i])
        else:
            self._transfer_erc20_from_contract(auction.currency_addr, royalty_recipients[1], royalty_fees[i])
        remaining_sale -= royalty_fees[i]
    
    # pay payout recipient
    if auction.currency_addr == empty(address):
        self._send_eth(auction.payout_receiver, remaining_sale)
    else:
        self._transfer_erc20_from_contract(auction.currency_addr, auction.payout_receiver, remaining_sale)

    # transfer NFT
    IERC721(nft_addr).transferFrom(self, auction.highest_bidder, token_id)

    log AuctionSettled(msg.sender, nft_addr, token_id, auction)

###########################################################################
#                        Sales Configuration Functions
###########################################################################

@external
def configure_sale(nft_addr: address, token_id: uint256, payout_receiver: address, currency_addr: address, price: uint256, merkle_root: bytes32):
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
    @param merkle_root The merkle root for making the sale private. An empty merkle root means it's open to the public
    """
    self._if_not_paused()
    nft_contract: IERC721 = IERC721(nft_addr)
    self._only_token_owner(nft_contract, token_id)
    self._is_auction_house_approved_for_all(nft_contract)

    sale: Sale = Sale({
        seller: msg.sender,
        payout_receiver: payout_receiver,
        currency_addr: currency_addr,
        price: price,
        merkle_root: merkle_root
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
    self._if_not_paused()
    sale: Sale = self._sales[nft_addr][token_id]
    self._only_sale_seller(sale)

    sale.currency_addr = currency_addr
    sale.price = price
    self._sales[nft_addr][token_id] = sale

    log SaleUpdated(msg.sender, nft_addr, token_id, sale)

@external
def update_sale_merkle_root(nft_addr: address, token_id: uint256, merkle_root: bytes32):
    """
    @notice Function to update the merkle root of the drop
    @dev Not allowed if the contract is paused
    @dev Requires that msg.sender is the nft seller
    @dev Requires the sale to be set
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param merkle_root The new merkle root for the sale
    """
    self._if_not_paused()
    sale: Sale = self._sales[nft_addr][token_id]
    self._only_sale_seller(sale)

    sale.merkle_root = merkle_root
    self._sales[nft_addr][token_id] = sale

    log SaleUpdated(msg.sender, nft_addr, token_id, sale)
    
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
    self._only_sale_seller(sale)

    self._sales[nft_addr][token_id] = empty(Sale)

    log SaleCanceled(msg.sender, nft_addr, token_id)

###########################################################################
#                             Buy Now Function
###########################################################################

@external
@payable
@nonreentrant("lock")
def buy_now(nft_addr: address, token_id: uint256, recipient: address, proof: DynArray[bytes32, max_value(uint16)]):
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
    @param recipient The receiver of the nft
    @param proof The merkle proof if a private sale is configured
    """
    # check pre-conditions
    self._if_not_paused()
    sale: Sale = self._sales[nft_addr][token_id]
    self._sale_exists(sale)
    self._not_sale_seller(sale)

    # check if private sale
    if sale.merkle_root != empty(bytes32):
        leaf: bytes32 = keccak256(convert(recipient, bytes32))
        self._verify_proof(proof, sale.merkle_root, leaf)

    # clear storage
    self._sales[nft_addr][token_id] = empty(Sale)
    self._auctions[nft_addr][token_id] = empty(Auction)

    # make external call to get and check royalty config
    royalty_recipients: DynArray[address, max_value(uint8)] = empty(DynArray[address, max_value(uint8)])
    royalty_fees: DynArray[uint256, max_value(uint8)] = empty(DynArray[uint256, max_value(uint8)])
    royalty_recipients, royalty_fees = self._get_royalty_info(nft_addr, token_id, sale.price)
    
    # pay royalties
    remaining_sale: uint256 = sale.price
    for i in range(0, 255):
        if i == len(royalty_recipients):
            break
        if sale.currency_addr == empty(address):
            self._send_eth(royalty_recipients[i], royalty_fees[i])
        else:
            self._transfer_erc20_from_address(sale.currency_addr, msg.sender, royalty_recipients[1], royalty_fees[i])
        remaining_sale -= royalty_fees[i]
    
    # pay payout reciever & refund eth if needed
    if sale.currency_addr == empty(address):
        self._send_eth(sale.payout_receiver, remaining_sale)
        refund: uint256 = msg.value - sale.price
        if refund > 0:
            self._send_eth(msg.sender, refund)
    else:
        self._transfer_erc20_from_address(sale.currency_addr, msg.sender, sale.payout_receiver, remaining_sale)
        if msg.value > 0:
            self._send_eth(msg.sender, msg.value)

    IERC721(nft_addr).transferFrom(sale.seller, recipient, token_id)

    log SaleFulfilled(msg.sender, nft_addr, token_id, recipient, sale)

###########################################################################
#                             Escrowed Eth Function
###########################################################################

@external
@payable
def withdraw_eth(recipient: address):
    """
    @notice function to withdraw any eth escrowed due to failed payout
    @dev anyone can call but will payout to the input recipient
    @dev if call reverts, eth is escrowed again
    """
    amount: uint256 = self._eth_escrowed[recipient]
    self._eth_escrowed[recipient] = 0
    self._send_eth(recipient, amount)

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

@external
@view
def get_auction(nft_addr: address, token_id: uint256) -> Auction:
    """
    @notice Function to get auction for an NFT
    @param nft_addr The nft contract address
    @param token_id The nft token id
    """
    return self._auctions[nft_addr][token_id]
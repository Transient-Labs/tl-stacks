# @version 0.3.9

"""
@title TLStacks1155
@notice Limited or Open Edition sales contracts for ERC1155TL contracts
@author transientlabs.xyz
@license MIT
@custom:version 2.0.0
"""

###########################################################################
#                              Interfaces
###########################################################################

interface IERC1155TL:
    def externalMint(tokenId: uint256, addresses: DynArray[address, 100], amounts: DynArray[uint256, 100]): nonpayable

interface IOwnableAccessControl:
    def owner() -> address: view
    def hasRole(role: bytes32, operator: address) -> bool: view

interface IERC20:
    def balanceOf(owner: address) -> uint256: view
    def allowance(owner: address, spender: address) -> uint256: view
    def transferFrom(from_: address, to: address, amount: uint256) -> bool: payable    

###########################################################################
#                              Constants
###########################################################################

ADMIN_ROLE: public(constant(bytes32)) = keccak256("ADMIN_ROLE")

###########################################################################
#                                Enums
###########################################################################

enum DropPhase:
    NOT_CONFIGURED
    BEFORE_SALE
    PRESALE
    PUBLIC_SALE
    ENDED

enum DropParam:
    MERKLE_ROOT
    ALLOWANCE
    COST
    DURATION
    START_TIME

###########################################################################
#                                Structs
###########################################################################

struct Drop:
    initial_supply: uint256
    supply: uint256
    allowance: uint256
    currency_addr: address
    payout_receiver: address
    start_time: uint256
    presale_duration: uint256
    presale_cost: uint256
    presale_merkle_root: bytes32
    public_duration: uint256
    public_cost: uint256

###########################################################################
#                                Events
###########################################################################

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event Paused:
    sender: indexed(address)
    status: indexed(bool)

event DropConfigured:
    configurer: indexed(address)
    nft_addr: indexed(address)
    block_number: indexed(uint256)
    token_id: uint256

event Purchase:
    buyer: indexed(address)
    receiver: indexed(address)
    nft_addr: indexed(address)
    token_id: uint256
    currency_addr: address
    amount: uint256
    price: uint256
    is_presale: bool

event DropClosed:
    closer: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)

event DropUpdated:
    updater: indexed(address)
    nft_addr: indexed(address)
    token_id: indexed(uint256)
    phase_param: DropPhase
    param_updated: DropParam
    value: bytes32

###########################################################################
#                            State Variables
###########################################################################

owner: public(address)
paused: public(bool)
_drops: HashMap[address, HashMap[uint256, Drop]]                                              # nft_addr -> token_id -> Drop
_num_minted: HashMap[address, HashMap[uint256, HashMap[uint256, HashMap[address, uint256]]]]  # nft_addr -> token_id -> round -> receiver -> num_minted
_drop_round: HashMap[address, HashMap[uint256, uint256]]                                      # nft_addr -> token_id -> round

###########################################################################
#                             Constructor
###########################################################################

@external
def __init__(init_owner: address):
    self._transfer_ownership(init_owner)


###########################################################################
#                         Owner Write Functions
###########################################################################

@external
def set_paused(paused: bool):
    """
    @notice function to pause or unpause the contract
    @dev requires msg.sender to be the contract owner
    @param paused A boolean with the pause state to set
    """
    assert msg.sender == self.owner, "caller not owner"
    self.paused = paused
    log Paused(msg.sender, paused)

@external
def transfer_ownership(new_owner: address):
    """
    @notice function to transfer ownership of the contract
    @dev requires msg.sender to be the contract owner
    @param new_owner The address to transfer ownership to
    """
    assert msg.sender == self.owner, "caller not owner"
    self._transfer_ownership(new_owner)

@internal
def _transfer_ownership(new_owner: address):
    """
    @dev logs an `OwnershipTransferred` event
    @param new_owner The address to transfer ownership to
    """
    prev_owner: address = self.owner
    self.owner = new_owner
    log OwnershipTransferred(prev_owner, new_owner)

###########################################################################
#                        Drop Configuration Functions
###########################################################################

@external 
def configure_drop(
    nft_addr: address,
    token_id: uint256,
    supply: uint256,
    allowance: uint256,
    currency_addr: address,
    payout_receiver: address,
    start_time: uint256,
    presale_duration: uint256,
    presale_cost: uint256,
    presale_merkle_root: bytes32,
    public_duration: uint256,
    public_cost: uint256
):
    """
    @notice function to configure a drop
    @dev contract cannot be paused
    @dev start_time cannot be zero
    @dev msg.sender must be nft contract owner or admin
    @dev a drop cannot already by configured
    @dev a non-zero decay rate cannot utilize an allowlist
    @param nft_addr The nft contract to set the drop for
    @param token_id The nft token id
    @param supply The supply for the drop
    @param allowance The number of nfts mintable during public sale
    @param currency_addr The currency address for ERC-20 tokens, or the zero address for ETH
    @param payout_receiver The address that receives the payout from the sale
    @param start_time The timestamp at which the sale starts
    @param presale_duration The duration in seconds for the presale
    @param presale_cost The cost of the presale, per token
    @param presale_merkle_root The merkle root for the presale allowlist
    @param public_duration The duration in seconds for the public sale
    @param public_cost The cost of the public sale, per token
    """
    assert not self.paused, "contract is paused"
    assert start_time != 0, "start time cannot be zero"
    assert self._is_drop_admin(nft_addr, msg.sender), "not authorized"
    assert self._get_drop_phase(nft_addr, token_id) == DropPhase.NOT_CONFIGURED, "there is an existing drop"

    drop: Drop = Drop({
        initial_supply: supply,
        supply: supply,
        allowance: allowance,
        currency_addr: currency_addr,
        payout_receiver: payout_receiver,
        start_time: start_time,
        presale_duration: presale_duration,
        presale_cost: presale_cost,
        presale_merkle_root: presale_merkle_root,
        public_duration: public_duration,
        public_cost: public_cost
    })

    self._drops[nft_addr][token_id] = drop

    log DropConfigured(msg.sender, nft_addr, block.number, token_id)

@external
def close_drop(nft_addr: address, token_id: uint256):
    """
    @notice function to close a drop
    @dev contract cannot be paused
    @dev msg.sender must be nft contract owner or admin
    @param nft_addr The nft contract to close the drop for
    @param token_id The token id on the contract
    """
    assert not self.paused, "contract is paused"
    assert self._is_drop_admin(nft_addr, msg.sender), "not authorized"
    
    self._drops[nft_addr][token_id] = empty(Drop)
    self._drop_round[nft_addr][token_id] += 1

    log DropClosed(msg.sender, nft_addr, token_id)

@external
def update_drop_param(
    nft_addr: address,
    token_id: uint256,
    phase: DropPhase, 
    param: DropParam, 
    param_value: bytes32
):
    """
    @notice function to update a drop parameter
    @dev contract cannot be paused
    @dev msg.sender must be nft contract owner or admin
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param phase The phase to update the param in
    @param param The param to update
    @param param_value The value to update the param to
    """
    assert not self.paused, "contract is paused"
    assert self._is_drop_admin(nft_addr, msg.sender), "not authorized"

    if phase == DropPhase.PRESALE:
        if param == DropParam.MERKLE_ROOT:
            self._drops[nft_addr][token_id].presale_merkle_root = param_value
        elif param == DropParam.COST:
            self._drops[nft_addr][token_id].presale_cost = convert(param_value, uint256)
        elif param == DropParam.DURATION:
            self._drops[nft_addr][token_id].presale_duration = convert(param_value, uint256)
        else:
            raise "unknown param update"
    elif phase == DropPhase.PUBLIC_SALE:
        if param == DropParam.ALLOWANCE:
            self._drops[nft_addr][token_id].allowance = convert(param_value, uint256)
        elif param == DropParam.COST:
            self._drops[nft_addr][token_id].public_cost = convert(param_value, uint256)
        elif param == DropParam.DURATION:
            self._drops[nft_addr][token_id].public_duration = convert(param_value, uint256)
        else:
            raise "unknown param update"
    elif phase == DropPhase.BEFORE_SALE:
        if param == DropParam.START_TIME:
            self._drops[nft_addr][token_id].start_time = convert(param_value, uint256)
        else:
            raise "unknown param update"
    else:
        raise "unknown param update"

    log DropUpdated(msg.sender, nft_addr, token_id, phase, param, param_value)


###########################################################################
#                            Mint Functions
###########################################################################

@external
@payable
@nonreentrant("mint different")
def mint(
    nft_addr: address,
    token_id: uint256,
    num_to_mint: uint256,
    receiver: address,
    proof: DynArray[bytes32, 3000],
    allowlist_allocation: uint256
):
    """
    @notice function to mint from a drop
    @dev contract cannot be paused
    @dev if presale, needs to be on the allowlist
    @dev supply must be left
    @dev must be able to pay mint cost and protocol fee, regardless of currency
    @param nft_addr The nft contract drop to mint from
    @param token_id The nft token id
    @param num_to_mint The number to mint
    @param receiver The receiver of the token(s)
    @param proof The merkle proof for the receiver
    @param allowlist_allocation The number of mints in the allowlist allowed
    """
    assert not self.paused, "contract is paused"
    assert num_to_mint > 0, "cannot mint zero tokens"
    drop: Drop = self._drops[nft_addr][token_id]
    assert drop.supply != 0, "no supply left"
    drop_phase: DropPhase = self._get_drop_phase(nft_addr, token_id)

    if drop_phase == DropPhase.PRESALE:
        leaf: bytes32 = keccak256(
            concat(
                convert(receiver, bytes32), 
                convert(allowlist_allocation, bytes32)
            )
        )
        assert self._verify_proof(proof, drop.presale_merkle_root, leaf), "not part of allowlist"

        num_can_mint: uint256 = self._determine_mint_num(
            nft_addr,
            token_id,
            receiver,
            num_to_mint,
            allowlist_allocation,
        )

        self._settle_up(
            nft_addr,
            token_id,
            receiver,
            num_can_mint,
            drop.presale_cost,
            drop.payout_receiver,
            drop.currency_addr
        )

        log Purchase(msg.sender, receiver, nft_addr, token_id, drop.currency_addr, num_can_mint, drop.presale_cost, True)

    elif drop_phase == DropPhase.PUBLIC_SALE:
        num_can_mint: uint256 = self._determine_mint_num(
            nft_addr,
            token_id,
            receiver,
            num_to_mint,
            drop.allowance
        )

        self._settle_up(
            nft_addr,
            token_id,
            receiver,
            num_can_mint,
            drop.public_cost,
            drop.payout_receiver,
            drop.currency_addr
        )

        log Purchase(msg.sender, receiver, nft_addr, token_id, drop.currency_addr, num_to_mint, drop.public_cost, False)

    else:
        raise "you shall not mint"

@internal
@payable
def _determine_mint_num(
    nft_addr: address,
    token_id: uint256,
    receiver: address,
    num_to_mint: uint256,
    allowance: uint256,
) -> uint256:
    """
    @notice function to determine how many tokens the receiver can mint
    @dev reverts if mint allowance is hit
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param receiver The address receiving the nfts
    @param num_to_mint The number requested to mint
    @param allowance The number of tokens receiver is allowed to mint
    @return uint256 The number of tokens allowed to mint
    """
    drop: Drop = self._drops[nft_addr][token_id]
    drop_round: uint256 = self._drop_round[nft_addr][token_id]
    curr_minted: uint256 = self._num_minted[nft_addr][token_id][drop_round][receiver]
    assert curr_minted < allowance, "already hit mint allowance"

    num_can_mint: uint256 = num_to_mint

    if curr_minted + num_to_mint > allowance:
        num_can_mint = allowance - curr_minted

    if num_can_mint > drop.supply:
        num_can_mint = drop.supply

    self._drops[nft_addr][token_id].supply -= num_can_mint
    self._num_minted[nft_addr][token_id][drop_round][receiver] += num_can_mint

    return num_can_mint

@internal
@payable
def _settle_up(
    nft_addr: address,
    token_id: uint256,
    receiver: address,
    num_can_mint: uint256,
    cost: uint256,
    payout_receiver: address,
    currency_addr: address
):
    """
    @notice function to settle up the payment
    @dev ensures token cost is paid in full
    @dev does not store any funds in the contract and passes payment through to the proper receivers
    @param nft_addr The nft contract to specify drop
    @param token_id The nft token id
    @param receiver The receiver of the token(s)
    @param num_can_mint The number that can be minted
    @param cost The cost per token in wei, or base unit of the ERC-20 token
    @param payout_receiver The address that receives the payout
    @param currency_addr The currency address
    """
    total_cost: uint256 = num_can_mint * cost

    if currency_addr == empty(address):
        assert msg.value >= total_cost, "not enough eth sent"
        self._send_eth(payout_receiver, total_cost)
        refund: uint256 = msg.value - total_cost
        self._send_eth(msg.sender, refund)

    else:
        self._transfer_erc20(currency_addr, payout_receiver, total_cost)
        if msg.value > 0:
            self._send_eth(msg.sender, msg.value)
    

    addrs: DynArray[address, 1] = [receiver]
    amts: DynArray[uint256, 1] = [num_can_mint]

    IERC1155TL(nft_addr).externalMint(token_id, addrs, amts)

@internal
@payable
def _send_eth(recipient: address, eth_amount: uint256):
    """
    @notice function to send eth, forwarding all gas
    @dev returns if eth_amount is zero
    @dev reverts on failure
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
def _transfer_erc20(erc20_addr: address, recipient: address, num_tokens: uint256):
    """
    @notice function to transfer ERC-20 tokens to a recipient, verifying that it was successful
    @dev returns if num_tokens is zero
    @dev reverts if contract does not have enough balance approved by the msg.sender
    @dev reverts on failure
    @dev checks that the balance transferred is accurate
    @dev if the msg.sender is the same as the recipient, then there is no need to transfer the tokens.
         This avoids reverting the transaction if the creator buys one and is also the payout receiver for the drop
    @param erc20_addr The address for erc20 token contract
    @param recipient The recipient for the erc20 tokens
    @param num_tokens The number of tokens to transfer
    """
    if num_tokens == 0 or msg.sender == recipient:
        return
    token: IERC20 = IERC20(erc20_addr)
    assert token.allowance(msg.sender, self) >= num_tokens, "not enough allowance given to contract"
    balance_before: uint256 = token.balanceOf(recipient)
    assert token.transferFrom(msg.sender, recipient, num_tokens, default_return_value=True), "ERC20 token transfer not successful"
    balance_after: uint256 = token.balanceOf(recipient)
    assert balance_after - balance_before == num_tokens, "insufficient ERC20 token transfer"

###########################################################################
#                         External Read Functions
###########################################################################

@view
@external
def get_drop(nft_addr: address, token_id: uint256) -> Drop:
    """
    @notice function to get drop details
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @return Drop The current drop parameters
    """
    return self._drops[nft_addr][token_id]

@view
@external
def get_num_minted(nft_addr: address, token_id: uint256, user: address) -> uint256:
    """
    @notice function to get number of nfts minted for a drop by and address
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @param user The user address to get number minted for
    @return uint256 The number of nfts minted by user for the drop
    """
    round_id: uint256 = self._drop_round[nft_addr][token_id]
    return self._num_minted[nft_addr][token_id][round_id][user]

@view
@external
def get_drop_phase(nft_addr: address, token_id: uint256) -> DropPhase:
    """
    @notice function to get current drop phase for the drop
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @return DropPhase The enum value showing current drop phase
    """
    return self._get_drop_phase(nft_addr, token_id)

@view
@external
def get_drop_round(nft_addr: address, token_id: uint256) -> uint256:
    """
    @notice function to get the current round for a drop
    @param nft_addr The nft contract address
    @param token_id The nft token id
    @return uint256 The drop round number
    """
    return self._drop_round[nft_addr][token_id]

###########################################################################
#                        Internal View/Pure Functions
###########################################################################

@view
@internal
def _is_drop_admin(nft_addr: address, operator: address) -> bool:
    """
    @notice function to check if operator is either the owner or admin on the nft contract
    @param nft_addr The nft contract address for the drop
    @param operator The operator address to check
    @return bool The verification if operator is a drop admin or not
    """
    return IOwnableAccessControl(nft_addr).owner() == operator \
        or IOwnableAccessControl(nft_addr).hasRole(ADMIN_ROLE, operator)

@view
@internal
def _get_drop_phase(nft_addr: address, token_id: uint256) -> DropPhase:
    """
    @notice function to get the drop phase
    @param nft_addr The nft contract address for the drop
    @param token_id The nft token id
    @return DropPhase The drop phase for the drops
    """
    drop: Drop = self._drops[nft_addr][token_id]

    if drop.start_time == 0:
        return DropPhase.NOT_CONFIGURED

    if drop.supply == 0:
        return DropPhase.ENDED

    if block.timestamp < drop.start_time:
        return DropPhase.BEFORE_SALE

    if block.timestamp >= drop.start_time and block.timestamp < drop.start_time + drop.presale_duration:
        return DropPhase.PRESALE

    if block.timestamp >= drop.start_time + drop.presale_duration \
        and block.timestamp < drop.start_time + drop.presale_duration + drop.public_duration:
        return DropPhase.PUBLIC_SALE

    return DropPhase.ENDED

@pure
@internal
def _verify_proof(proof: DynArray[bytes32, max_value(uint16)], root: bytes32, leaf: bytes32) -> bool:
    """
    @notice function to verify a merkle proof
    @param proof The merkle proof
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
    return computed_hash == root

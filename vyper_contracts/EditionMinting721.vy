# @version 0.3.7
# SPDX-License-Identifier: Apache-2.0

#    ____        _ __    __   ____  _ ________                     __ 
#   / __ )__  __(_) /___/ /  / __ \(_) __/ __/__  ________  ____  / /_
#  / __  / / / / / / __  /  / / / / / /_/ /_/ _ \/ ___/ _ \/ __ \/ __/
# / /_/ / /_/ / / / /_/ /  / /_/ / / __/ __/  __/ /  /  __/ / / / /__ 
#/_____/\__,_/_/_/\__,_/  /_____/_/_/ /_/  \___/_/   \___/_/ /_/\__(_)

#//////////////////////////////////////////////////////////////////////////
#                              Interfaces
#//////////////////////////////////////////////////////////////////////////

interface IERC721TL:
    def externalMint(recipient: address, uri: String[1337]): nonpayable

interface IOwnableAccessControl:
    def owner() -> address: view
    def hasRole(role: bytes32, operator: address) -> bool: view
    

#//////////////////////////////////////////////////////////////////////////
#                              Constants
#//////////////////////////////////////////////////////////////////////////

ADMIN_ROLE: constant(bytes32) = keccak256("ADMIN_ROLE")

#//////////////////////////////////////////////////////////////////////////
#                                Enums
#//////////////////////////////////////////////////////////////////////////

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
    PAYOUT_ADDRESS

#//////////////////////////////////////////////////////////////////////////
#                                Struct
#//////////////////////////////////////////////////////////////////////////

struct Drop:
    base_uri: String[100]
    initial_supply: uint256
    supply: uint256
    decay_rate: int256
    allowance: uint256
    payout_receiver: address
    start_time: uint256
    presale_duration: uint256
    presale_cost: uint256
    presale_merkle_root: bytes32
    public_duration: uint256
    public_cost: uint256

#//////////////////////////////////////////////////////////////////////////
#                                Events
#//////////////////////////////////////////////////////////////////////////

event Payment:
    amount: int128
    sender: indexed(address)

event OwnershipTransferred:
    previousOwner: indexed(address)
    newOwner: indexed(address)

event DropConfigured:
    configurer: indexed(address)
    nft_contract: indexed(address)
    token_id: uint256

event Purchase:
    buyer: indexed(address)
    nft_addr: indexed(address)
    amount: uint256
    price: uint256
    is_presale: bool

event DropClosed:
    closer: indexed(address)
    nft_contract: indexed(address)
    token_id: uint256

event DropUpdated:
    phase_param: DropPhase
    param_updated: DropParam
    value: bytes32

event Paused:
    status: bool

#//////////////////////////////////////////////////////////////////////////
#                                Contract Vars
#//////////////////////////////////////////////////////////////////////////
owner: public(address)

# nft_caddr => token_id => Drop
drops: HashMap[address, HashMap[uint256, Drop]]

# nft_caddr => token_id => round_id => user => num_minted
num_minted: HashMap[address, HashMap[uint256, HashMap[uint256, HashMap[address, uint256]]]]

# nft_addr => token_id => round_num
drop_round: HashMap[address, HashMap[uint256, uint256]]

# determine if the contract is paused or not
paused: bool

#//////////////////////////////////////////////////////////////////////////
#                                Constructor
#//////////////////////////////////////////////////////////////////////////

@external
def __init__(_owner: address):
    self.owner = _owner
    log OwnershipTransferred(empty(address), _owner)

#//////////////////////////////////////////////////////////////////////////
#                         Owner Write Function
#//////////////////////////////////////////////////////////////////////////

@external
def set_paused(paused: bool):
    if self.owner != msg.sender:
        raise "not authorized"

    self.paused = paused

    log Paused(paused)

#//////////////////////////////////////////////////////////////////////////
#                         Admin Write Function
#//////////////////////////////////////////////////////////////////////////

@external 
def configure_drop(
    nft_addr: address,
    token_id: uint256,
    base_uri: String[100],
    supply: uint256,
    decay_rate: int256,
    allowance: uint256,
    payout_receiver: address,
    start_time: uint256,
    presale_duration: uint256,
    presale_cost: uint256,
    presale_merkle_root: bytes32,
    public_duration: uint256,
    public_cost: uint256
):
    # Check if paused
    if self.paused:
        raise "contract is paused"

    if start_time == 0:
        raise "start time cannot be 0"

    # Make sure the sender is the owner or admin on the contract
    if not self.is_drop_admin(nft_addr, msg.sender):
        raise "not authorized"

    drop: Drop = self.drops[nft_addr][token_id]

    # Check if theres an existing drop that needs to be closed
    if drop.supply != 0:
        raise "there is an existing drop"

    # Allowlist doesnt work with burn down/extending mints
    if decay_rate != 0 and presale_duration != 0:
        raise "cant have allowlist with burn/extending"

    # No supply for velocity mint
    if decay_rate < 0 and supply != max_value(uint256):
        raise "cant have burn down and a supply"

    drop = Drop({
        base_uri: base_uri,
        initial_supply: supply,
        supply: supply,
        decay_rate: decay_rate,
        allowance: allowance,
        payout_receiver: payout_receiver,
        start_time: start_time,
        presale_duration: presale_duration,
        presale_cost: presale_cost,
        presale_merkle_root: presale_merkle_root,
        public_duration: public_duration,
        public_cost: public_cost
    })

    self.drops[nft_addr][token_id] = drop

    log DropConfigured(msg.sender, nft_addr, token_id)

@external
def close_drop(
    nft_addr: address,
    token_id: uint256
):
    if self.paused:
        raise "contract is paused"
        
    if not self.is_drop_admin(nft_addr, msg.sender):
        raise "unauthorized"
    
    self.drops[nft_addr][token_id] = empty(Drop)
    self.drop_round[nft_addr][token_id] += 1

    log DropClosed(msg.sender, nft_addr, token_id)

@external
def update_drop_param(
    nft_addr: address, 
    token_id: uint256, 
    phase: DropPhase, 
    param: DropParam, 
    param_value: bytes32
):
    if not self.is_drop_admin(nft_addr, msg.sender):
        raise "unauthorized"

    if phase == DropPhase.PRESALE:
        if param == DropParam.MERKLE_ROOT:
            self.drops[nft_addr][token_id].presale_merkle_root = param_value
        elif param == DropParam.COST:
            self.drops[nft_addr][token_id].presale_cost = convert(param_value, uint256)
        elif param == DropParam.DURATION:
            self.drops[nft_addr][token_id].presale_duration = convert(param_value, uint256)
        else:
            raise "unknown param update"
    elif phase == DropPhase.PUBLIC_SALE:
        if param == DropParam.ALLOWANCE:
            self.drops[nft_addr][token_id].allowance = convert(param_value, uint256)
        elif param == DropParam.COST:
            self.drops[nft_addr][token_id].presale_cost = convert(param_value, uint256)
        elif param == DropParam.DURATION:
            self.drops[nft_addr][token_id].public_duration = convert(param_value, uint256)
        else:
            raise "unknown param update"
    elif phase == DropPhase.NOT_CONFIGURED:
        if param == DropParam.PAYOUT_ADDRESS:
            self.drops[nft_addr][token_id].payout_receiver = convert(param_value, address)
        else:
            raise "unknown param update"
    else:
        raise "unknown param update"

    log DropUpdated(phase, param, param_value)


#//////////////////////////////////////////////////////////////////////////
#                         External Write Function
#//////////////////////////////////////////////////////////////////////////

@external
@payable
@nonreentrant("lock")
def mint(
    nft_addr: address,
    token_id: uint256,
    num_mint: uint256,
    proof: DynArray[bytes32, 100],
    allowlist_allocation: uint256
):
    if self.paused:
        raise "contract is paused"

    drop: Drop = self.drops[nft_addr][token_id]

    if drop.supply == 0:
        raise "no supply left"
    
    drop_phase: DropPhase = self._get_drop_phase(nft_addr, token_id)

    if drop_phase == DropPhase.PRESALE:
        leaf: bytes32 = keccak256(concat(convert(msg.sender, bytes32), convert(allowlist_allocation, bytes32)))
        root: bytes32 = self.drops[nft_addr][token_id].presale_merkle_root
        
        # Check if user is part of allowlist
        if not self.verify_proof(proof, root, leaf):
            raise "not part of allowlist"

        drop_round: uint256 = self.drop_round[nft_addr][token_id]
        curr_minted: uint256 = self.num_minted[nft_addr][token_id][drop_round][msg.sender]

        mint_num: uint256 = num_mint

        if curr_minted == allowlist_allocation:
            raise "already hit mint allowance"
        elif curr_minted + num_mint > allowlist_allocation:
            mint_num = allowlist_allocation - curr_minted
        
        if mint_num > drop.supply:
            mint_num = drop.supply

        if msg.value < mint_num * drop.presale_cost:
            raise "not enough funds sent"

        self.drops[nft_addr][token_id].supply -= mint_num
        self.num_minted[nft_addr][token_id][drop_round][msg.sender] += mint_num

        if mint_num != num_mint:
            diff: uint256 = num_mint - mint_num
            raw_call(
                msg.sender,
                _abi_encode(""),
                max_outsize=0,
                value=msg.value-(mint_num * drop.presale_cost),
                revert_on_failure=True
            )

        token_id_counter: uint256 = drop.initial_supply - self.drops[nft_addr][token_id].supply - mint_num
        
        for i in range(0, max_value(uint8)):
            if i == mint_num:
                break
            IERC721TL(nft_addr).externalMint(msg.sender, concat(drop.base_uri, uint2str(token_id_counter)))
            token_id_counter += 1

        log Purchase(msg.sender, nft_addr, mint_num, drop.presale_cost, True)

    elif drop_phase == DropPhase.PUBLIC_SALE:
        if block.timestamp > drop.start_time + drop.presale_duration + drop.public_duration:
            raise "public sale is no more"

        drop_round: uint256 = self.drop_round[nft_addr][token_id]
        curr_minted: uint256 = self.num_minted[nft_addr][token_id][drop_round][msg.sender]

        mint_num: uint256 = num_mint

        if curr_minted >= drop.allowance:
            raise "already hit mint allowance"
        elif curr_minted + num_mint > drop.allowance:
            mint_num = drop.allowance - curr_minted
        
        if mint_num > drop.supply:
            mint_num = drop.supply

        if msg.value < mint_num * drop.public_cost:
            raise "not enough funds sent"

        self.drops[nft_addr][token_id].supply -= mint_num
        self.num_minted[nft_addr][token_id][drop_round][msg.sender] += mint_num

        if drop.decay_rate != 0:
            adjust: uint256 = mint_num * convert(drop.decay_rate, uint256)
            if drop.decay_rate < 0:
                self.drops[nft_addr][token_id].public_duration -= adjust
            else:
                self.drops[nft_addr][token_id].public_duration += adjust

        if mint_num != num_mint:
            diff: uint256 = num_mint - mint_num
            raw_call(
                msg.sender,
                _abi_encode(""),
                max_outsize=0,
                value=msg.value-(mint_num * drop.presale_cost),
                revert_on_failure=True
            )
        
        token_id_counter: uint256 = drop.initial_supply - self.drops[nft_addr][token_id].supply - mint_num

        for i in range(0, max_value(uint8)):
            if i == mint_num:
                break
            IERC721TL(nft_addr).externalMint(msg.sender, concat(drop.base_uri, uint2str(token_id_counter)))
            token_id_counter += 1

        log Purchase(msg.sender, nft_addr, mint_num, drop.public_cost, True)

    else:
        raise "you shall not mint"

#//////////////////////////////////////////////////////////////////////////
#                         External Read Function
#//////////////////////////////////////////////////////////////////////////

@view
@external
def get_drop(nft_addr: address, token_id: uint256) -> Drop:
    return self.drops[nft_addr][token_id]

@view
@external
def get_num_minted(nft_addr: address, token_id: uint256, user: address) -> uint256:
    round_id: uint256 = self.drop_round[nft_addr][token_id]
    return self.num_minted[nft_addr][token_id][round_id][user]

@view
@external
def get_drop_phase(nft_addr: address, token_id: uint256) -> DropPhase:
    return self._get_drop_phase(nft_addr, token_id)

@view
@external
def is_paused() -> bool:
    return self.paused

#//////////////////////////////////////////////////////////////////////////
#                         Internal Read Function
#//////////////////////////////////////////////////////////////////////////

@view
@internal
def is_drop_admin(nft_addr: address, operator: address) -> bool:
    return IOwnableAccessControl(nft_addr).owner() == operator \
        or IOwnableAccessControl(nft_addr).hasRole(ADMIN_ROLE, operator)

@view
@internal
def _get_drop_phase(nft_addr: address, token_id: uint256) -> DropPhase:
    drop: Drop = self.drops[nft_addr][token_id]

    if drop.start_time == 0:
        return DropPhase.NOT_CONFIGURED

    if block.timestamp < drop.start_time:
        return DropPhase.BEFORE_SALE

    if drop.start_time <= block.timestamp and block.timestamp < drop.start_time + drop.presale_duration:
        return DropPhase.PRESALE

    if drop.start_time + drop.presale_duration <= block.timestamp \
        and block.timestamp < drop.start_time + drop.presale_duration + drop.public_duration:
        return DropPhase.PUBLIC_SALE

    return DropPhase.ENDED

@pure
@internal
def verify_proof(proof: DynArray[bytes32, 100], root: bytes32, leaf: bytes32) -> bool:
    computed_hash: bytes32 = leaf
    for p in proof:
        if convert(computed_hash, uint256) < convert(p, uint256):
            computed_hash = keccak256(concat(computed_hash, p))  
        else: 
            computed_hash = keccak256(concat(p, computed_hash))
    return computed_hash == root

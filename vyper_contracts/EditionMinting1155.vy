# @version 0.3.7

from interfaces.IERC1155TL import IERC1155TL
from interfaces.IOwnableAccessControl import IOwnableAccessControl

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
    nft_addr: address
    token_id: uint256
    supply: uint256
    decay_rate: int256
    allowance: uint256
    payout_receiver: address
    presale_start_time: uint256
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
    supply: uint256,
    decay_rate: int256,
    allowance: uint256,
    payout_receiver: address,
    presale_start_time: uint256,
    presale_duration: uint256,
    presale_cost: uint256,
    presale_merkle_root: bytes32,
    public_duration: uint256,
    public_cost: uint256
):
    # Check if paused
    if self.paused:
        raise "contract is paused"

    # Make sure the sender is the owner or admin on the contract
    if not self.is_drop_admin(nft_addr, msg.sender):
        raise "not authorized"

    drop: Drop = self.drops[nft_addr][token_id]

    # Check if theres an existing drop that needs to be closed
    if drop.supply != 0:
        raise "there is an existing drop"

    # Allowlist doesnt work with burn down/extending mints
    if decay_rate != 0 and (presale_start_time != 0 or presale_duration != 0 \
        or presale_merkle_root != empty(bytes32)):
        raise "cant have allowlist with burn/extending"

    # No supply for velocity mint
    if decay_rate < 0 and supply != max_value(uint256):
        raise "cant have burn down and a supply"

    drop = Drop({
        nft_addr: nft_addr,
        token_id: token_id,
        supply: supply,
        decay_rate: decay_rate,
        allowance: allowance,
        payout_receiver: payout_receiver,
        presale_start_time: presale_start_time,
        presale_duration: presale_duration,
        presale_cost: presale_cost,
        presale_merkle_root: presale_merkle_root,
        public_duration: public_duration,
        public_cost: public_cost
    })

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
        
        addrs: DynArray[address, 1] = [msg.sender]
        amts: DynArray[uint256, 1] = [mint_num]

        IERC1155TL(nft_addr).mintToken(token_id, addrs, amts)

    elif drop_phase == DropPhase.PUBLIC_SALE:
        pass
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

    if drop.supply == 0:
        return DropPhase.NOT_CONFIGURED

    if block.timestamp < drop.presale_start_time:
        return DropPhase.BEFORE_SALE

    if drop.presale_start_time <= block.timestamp and block.timestamp < drop.presale_start_time + drop.presale_duration:
        return DropPhase.PRESALE

    if drop.presale_start_time + drop.presale_duration <= block.timestamp \
        and block.timestamp < drop.presale_start_time + drop.presale_duration + drop.public_duration:
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

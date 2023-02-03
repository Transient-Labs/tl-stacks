# @version 0.3.7

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

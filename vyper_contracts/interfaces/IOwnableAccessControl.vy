# @version 0.3.7

# interface IOwnableAccessControl:
#     def owner() -> address: view
#     def hasRole(role: bytes32, operator: address) -> bool: view

@view
@external
def owner() -> address:
    pass

@view
@external
def hasRole(role: bytes32, operator: address) -> bool:
    pass

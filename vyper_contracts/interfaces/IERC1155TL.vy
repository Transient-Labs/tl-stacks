# @version 0.3.7

# interface IERC1155:
#     def mintToken(tokenId: uint256, addresses: DynArray[address, 100], amounts: DynArray[uint256, 100]): nonpayable

@external
def mintToken(tokenId: uint256, addresses: DynArray[address, 100], amounts: DynArray[uint256, 100]):
    pass

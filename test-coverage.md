| File                          | % Lines           | % Statements      | % Branches        | % Funcs         |
|-------------------------------|-------------------|-------------------|-------------------|-----------------|
| src/TLAuctionHouse.sol        | 99.36% (155/156)  | 99.52% (208/209)  | 100.00% (52/52)   | 100.00% (20/20) |
| src/TLStacks1155.sol          | 100.00% (180/180) | 100.00% (261/261) | 100.00% (54/54)   | 100.00% (32/32) |
| src/TLStacks721.sol           | 100.00% (175/175) | 100.00% (255/255) | 100.00% (54/54)   | 100.00% (31/31) |
| src/helpers/CreatorLookup.sol | 100.00% (5/5)     | 100.00% (8/8)     | 100.00% (0/0)     | 100.00% (1/1)   |
| src/helpers/RoyaltyLookup.sol | 100.00% (35/35)   | 100.00% (49/49)   | 100.00% (4/4)     | 100.00% (3/3)   |
| Total                         | 99.82% (550/551)  | 99.87% (781/782)  | 100.00% (164/164) | 100.00% (87/87) |

Forge coverage says that line 562 in `TLAuctionHouse.sol` isn't tested, but that's not true and is flagged because it's an empty `catch` statement.
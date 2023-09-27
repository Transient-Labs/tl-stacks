# Bid gas comparison

## using flags + `sAuction` (cheaper)

| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |       |        |        |         |
|------------------------------------------------|-----------------|-------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |       |        |        |         |
| 2882560                                        | 14220           |       |        |        |         |
| Function Name                                  | min             | avg   | median | max    | # calls |
| bid                                            | 634             | 52372 | 25453  | 155805 | 42      |
| buyNow                                         | 592             | 34289 | 28812  | 107566 | 14      |
| calcNextMinBid                                 | 1370            | 3650  | 3317   | 7265   | 12      |
| calcProtocolFee                                | 775             | 2599  | 880    | 4880   | 18      |
| cancelAuction                                  | 3734            | 12886 | 4773   | 38266  | 4       |
| cancelSale                                     | 4299            | 12390 | 4299   | 28573  | 3       |
| configureAuction                               | 936             | 90377 | 117600 | 157400 | 22      |
| configureSale                                  | 849             | 59322 | 75286  | 127186 | 18      |
| getAuction                                     | 2400            | 2400  | 2400   | 2400   | 16      |
| getSale                                        | 1564            | 1564  | 1564   | 1564   | 10      |
| minBidIncreaseLimit                            | 353             | 1353  | 1353   | 2353   | 2       |
| minBidIncreasePerc                             | 329             | 1329  | 1329   | 2329   | 2       |
| owner                                          | 2398            | 2398  | 2398   | 2398   | 1       |
| pause                                          | 1603            | 3682  | 2590   | 6814   | 5       |
| paused                                         | 370             | 370   | 370    | 370    | 1       |
| protocolFeeLimit                               | 396             | 1396  | 1396   | 2396   | 2       |
| protocolFeePerc                                | 352             | 1352  | 1352   | 2352   | 2       |
| protocolFeeReceiver                            | 404             | 1404  | 1404   | 2404   | 2       |
| royaltyEngine                                  | 383             | 383   | 383    | 383    | 1       |
| setMinBidIncreaseSettings                      | 2594            | 7352  | 7352   | 12111  | 2       |
| setProtocolFeeSettings                         | 2686            | 10159 | 10159  | 17633  | 2       |
| setRoyaltyEngine                               | 2667            | 4199  | 4199   | 5731   | 2       |
| setWethAddress                                 | 2644            | 4178  | 4178   | 5712   | 2       |
| settleAuction                                  | 4964            | 38235 | 24843  | 80236  | 5       |
| transferOwnership                              | 2643            | 3521  | 3521   | 4400   | 2       |
| weth                                           | 426             | 1426  | 1426   | 2426   | 2       |

## setting entire auction struct (more expensive)

| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |       |        |        |         |
|------------------------------------------------|-----------------|-------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |       |        |        |         |
| 2893775                                        | 14276           |       |        |        |         |
| Function Name                                  | min             | avg   | median | max    | # calls |
| bid                                            | 634             | 53034 | 26052  | 156876 | 42      |
| buyNow                                         | 592             | 35438 | 28812  | 123654 | 14      |
| calcNextMinBid                                 | 1370            | 3650  | 3317   | 7265   | 12      |
| calcProtocolFee                                | 775             | 2611  | 880    | 4880   | 18      |
| cancelAuction                                  | 3734            | 12886 | 4773   | 38266  | 4       |
| cancelSale                                     | 4299            | 12390 | 4299   | 28573  | 3       |
| configureAuction                               | 936             | 90377 | 117600 | 157400 | 22      |
| configureSale                                  | 849             | 59322 | 75286  | 127186 | 18      |
| getAuction                                     | 2400            | 2400  | 2400   | 2400   | 16      |
| getSale                                        | 1564            | 1564  | 1564   | 1564   | 10      |
| minBidIncreaseLimit                            | 353             | 1353  | 1353   | 2353   | 2       |
| minBidIncreasePerc                             | 329             | 1329  | 1329   | 2329   | 2       |
| owner                                          | 2398            | 2398  | 2398   | 2398   | 1       |
| pause                                          | 1603            | 3682  | 2590   | 6814   | 5       |
| paused                                         | 370             | 370   | 370    | 370    | 1       |
| protocolFeeLimit                               | 396             | 1396  | 1396   | 2396   | 2       |
| protocolFeePerc                                | 352             | 1352  | 1352   | 2352   | 2       |
| protocolFeeReceiver                            | 404             | 1404  | 1404   | 2404   | 2       |
| royaltyEngine                                  | 383             | 383   | 383    | 383    | 1       |
| setMinBidIncreaseSettings                      | 2594            | 7352  | 7352   | 12111  | 2       |
| setProtocolFeeSettings                         | 2686            | 10159 | 10159  | 17633  | 2       |
| setRoyaltyEngine                               | 2667            | 4199  | 4199   | 5731   | 2       |
| setWethAddress                                 | 2644            | 4178  | 4178   | 5712   | 2       |
| settleAuction                                  | 4964            | 38235 | 24843  | 80236  | 5       |
| transferOwnership                              | 2643            | 3521  | 3521   | 4400   | 2       |
| weth                                           | 426             | 1426  | 1426   | 2426   | 2       |
# Gas Test Results
Version 2.2.0

| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |        |        |        |         |
|------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |        |        |        |         |
| 3172254                                        | 15796           |        |        |        |         |
| Function Name                                  | min             | avg    | median | max    | # calls |
| bid                                            | 612             | 47984  | 29176  | 159859 | 67      |
| buyNow                                         | 659             | 32032  | 21730  | 123676 | 18      |
| calcNextMinBid                                 | 1348            | 3313   | 1348   | 7243   | 24      |
| calcProtocolFee                                | 753             | 2468   | 858    | 4858   | 34      |
| cancelAuction                                  | 6898            | 12403  | 8440   | 40766  | 7       |
| cancelSale                                     | 6344            | 10620  | 7507   | 31599  | 7       |
| configureAuction                               | 982             | 110083 | 122435 | 182145 | 32      |
| configureSale                                  | 916             | 63084  | 74033  | 132033 | 23      |
| getAuction                                     | 2356            | 2356   | 2356   | 2356   | 24      |
| getSale                                        | 1630            | 1630   | 1630   | 1630   | 10      |
| minBidIncreaseLimit                            | 353             | 1353   | 1353   | 2353   | 2       |
| minBidIncreasePerc                             | 396             | 1396   | 1396   | 2396   | 2       |
| owner                                          | 2376            | 2376   | 2376   | 2376   | 1       |
| pause                                          | 1603            | 3682   | 2590   | 6814   | 5       |
| paused                                         | 415             | 415    | 415    | 415    | 1       |
| protocolFeeLimit                               | 374             | 1374   | 1374   | 2374   | 2       |
| protocolFeePerc                                | 330             | 1330   | 1330   | 2330   | 2       |
| protocolFeeReceiver                            | 382             | 1382   | 1382   | 2382   | 2       |
| royaltyEngine                                  | 448             | 448    | 448    | 448    | 1       |
| setMinBidIncreaseSettings                      | 2581            | 5762   | 2594   | 12111  | 3       |
| setProtocolFeeSettings                         | 2654            | 7643   | 2664   | 17611  | 3       |
| setRoyaltyEngine                               | 2645            | 4179   | 4179   | 5713   | 2       |
| setSanctionsOracle                             | 26247           | 26247  | 26247  | 26247  | 1       |
| setWethAddress                                 | 2644            | 4178   | 4178   | 5712   | 2       |
| settleAuction                                  | 4818            | 54159  | 68742  | 81784  | 9       |
| transferOwnership                              | 2643            | 3521   | 3521   | 4400   | 2       |
| weth                                           | 404             | 1404   | 1404   | 2404   | 2       |


| src/TLStacks1155.sol:TLStacks1155 contract |                 |        |        |        |         |
|--------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                            | Deployment Size |        |        |        |         |
| 3366109                                    | 16921           |        |        |        |         |
| Function Name                              | min             | avg    | median | max    | # calls |
| closeDrop                                  | 8231            | 18517  | 22796  | 24396  | 6       |
| configureDrop                              | 718             | 156804 | 197660 | 277260 | 42      |
| getDrop                                    | 3208            | 3208   | 3208   | 3208   | 59      |
| getDropPhase                               | 2511            | 4537   | 2545   | 26479  | 13      |
| getDropRound                               | 705             | 1705   | 1705   | 2705   | 2       |
| getDrops                                   | 7197            | 7197   | 7197   | 7197   | 1       |
| getNumberMinted                            | 1220            | 2220   | 2220   | 3220   | 2       |
| owner                                      | 2420            | 2420   | 2420   | 2420   | 1       |
| pause                                      | 1603            | 3682   | 2590   | 6814   | 5       |
| paused                                     | 348             | 348    | 348    | 348    | 1       |
| protocolFee                                | 373             | 1373   | 1373   | 2373   | 2       |
| protocolFeeReceiver                        | 383             | 1383   | 1383   | 2383   | 2       |
| purchase                                   | 4765            | 62387  | 70639  | 143135 | 52      |
| setProtocolFeeSettings                     | 2621            | 6170   | 6170   | 9719   | 2       |
| setSanctionsOracle                         | 26291           | 26291  | 26291  | 26291  | 1       |
| setWethAddress                             | 2600            | 4150   | 4150   | 5700   | 2       |
| transferOwnership                          | 2643            | 3521   | 3521   | 4400   | 2       |
| updateDropAllowance                        | 701             | 14552  | 10756  | 44056  | 6       |
| updateDropDecayRate                        | 657             | 12668  | 8668   | 44012  | 7       |
| updateDropDuration                         | 7742            | 24058  | 19842  | 44090  | 6       |
| updateDropPayoutReceiver                   | 716             | 12885  | 9995   | 46270  | 8       |
| updateDropPresaleMerkleRoot                | 656             | 17750  | 11503  | 44011  | 6       |
| updateDropPrices                           | 800             | 21456  | 12006  | 50958  | 6       |
| weth                                       | 405             | 1405   | 1405   | 2405   | 2       |


| src/TLStacks721.sol:TLStacks721 contract |                 |        |        |        |         |
|------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                          | Deployment Size |        |        |        |         |
| 3963868                                  | 19906           |        |        |        |         |
| Function Name                            | min             | avg    | median | max    | # calls |
| closeDrop                                | 8072            | 18361  | 22619  | 24219  | 6       |
| configureDrop                            | 678             | 176338 | 221562 | 306206 | 43      |
| getDrop                                  | 3892            | 4136   | 4136   | 4421   | 52      |
| getDropPhase                             | 3134            | 5222   | 3499   | 28929  | 14      |
| getDropRound                             | 541             | 1541   | 1541   | 2541   | 2       |
| getNumberMinted                          | 994             | 1994   | 1994   | 2994   | 2       |
| owner                                    | 2352            | 2352   | 2352   | 2352   | 1       |
| pause                                    | 1584            | 3664   | 2578   | 6790   | 5       |
| paused                                   | 393             | 393    | 393    | 393    | 1       |
| protocolFee                              | 373             | 1373   | 1373   | 2373   | 2       |
| protocolFeeReceiver                      | 381             | 1381   | 1381   | 2381   | 2       |
| purchase                                 | 4624            | 103700 | 115549 | 238757 | 48      |
| setProtocolFeeSettings                   | 2620            | 6164   | 6164   | 9708   | 2       |
| setSanctionsOracle                       | 26233           | 26233  | 26233  | 26233  | 1       |
| setWethAddress                           | 2576            | 4124   | 4124   | 5672   | 2       |
| transferOwnership                        | 2597            | 3463   | 3463   | 4330   | 2       |
| updateDropAllowance                      | 669             | 15629  | 12090  | 46476  | 6       |
| updateDropDecayRate                      | 648             | 13471  | 8626   | 46455  | 7       |
| updateDropDuration                       | 8315            | 24458  | 18398  | 46490  | 6       |
| updateDropPayoutReceiver                 | 738             | 13823  | 10711  | 48732  | 8       |
| updateDropPresaleMerkleRoot              | 604             | 18824  | 12881  | 46411  | 6       |
| updateDropPrices                         | 700             | 22500  | 13392  | 52336  | 6       |
| weth                                     | 403             | 1403   | 1403   | 2403   | 2       |
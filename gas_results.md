| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |        |        |        |         |
|------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |        |        |        |         |
| 3331668                                        | 15340           |        |        |        |         |
| Function Name                                  | min             | avg    | median | max    | # calls |
| bid                                            | 24258           | 106663 | 86227  | 231020 | 14080   |
| buyNow                                         | 24165           | 165778 | 156845 | 184492 | 528     |
| calcNextMinBid                                 | 1243            | 3284   | 1348   | 7243   | 6144    |
| calcProtocolFee                                | 753             | 2296   | 858    | 4858   | 8194    |
| cancelAuction                                  | 56602           | 57419  | 57164  | 59416  | 1792    |
| cancelSale                                     | 47590           | 48331  | 48048  | 52083  | 1792    |
| configureAuction                               | 25340           | 145113 | 168504 | 209238 | 5897    |
| configureSale                                  | 24970           | 88638  | 64466  | 158810 | 3338    |
| getAuction                                     | 2356            | 2356   | 2356   | 2356   | 4869    |
| getSale                                        | 1630            | 1630   | 1630   | 1630   | 1285    |
| minBidIncreaseLimit                            | 353             | 360    | 353    | 2353   | 257     |
| minBidIncreasePerc                             | 396             | 403    | 396    | 2396   | 257     |
| owner                                          | 2376            | 2376   | 2376   | 2376   | 1       |
| pause                                          | 23742           | 25879  | 27995  | 28018  | 1025    |
| paused                                         | 415             | 415    | 415    | 415    | 1       |
| protocolFeeLimit                               | 374             | 381    | 374    | 2374   | 257     |
| protocolFeePerc                                | 330             | 337    | 330    | 2330   | 257     |
| protocolFeeReceiver                            | 382             | 389    | 382    | 2382   | 257     |
| royaltyEngine                                  | 448             | 448    | 448    | 448    | 256     |
| setMinBidIncreaseSettings                      | 23970           | 29737  | 23997  | 35527  | 513     |
| setProtocolFeeSettings                         | 24168           | 32845  | 24438  | 41395  | 513     |
| setRoyaltyEngine                               | 23797           | 24665  | 24665  | 25533  | 512     |
| setSanctionsOracle                             | 47679           | 47679  | 47679  | 47679  | 1       |
| setWethAddress                                 | 23796           | 24664  | 24664  | 25532  | 512     |
| settleAuction                                  | 46390           | 106284 | 144868 | 172563 | 1794    |
| transferOwnership                              | 23795           | 24894  | 24933  | 25832  | 512     |
| weth                                           | 404             | 411    | 404    | 2404   | 257     |


| src/TLStacks1155.sol:TLStacks1155 contract |                 |        |        |        |         |
|--------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                            | Deployment Size |        |        |        |         |
| 3884191                                    | 18055           |        |        |        |         |
| Function Name                              | min             | avg    | median | max    | # calls |
| closeDrop                                  | 37849           | 68503  | 80328  | 84808  | 1026    |
| configureDrop                              | 26069           | 227361 | 222001 | 300845 | 5398    |
| freeMintFeeSplit                           | 372             | 379    | 372    | 2372   | 281     |
| getDrop                                    | 3252            | 3252   | 3252   | 3252   | 13921   |
| getDropPhase                               | 2578            | 2804   | 2578   | 26546  | 1668    |
| getDropRound                               | 705             | 708    | 705    | 2705   | 516     |
| getDrops                                   | 7063            | 7063   | 7063   | 7063   | 1       |
| getNumberMinted                            | 1220            | 2220   | 2220   | 3220   | 512     |
| owner                                      | 2376            | 2376   | 2376   | 2376   | 1       |
| pause                                      | 23742           | 25879  | 27995  | 28018  | 1025    |
| paused                                     | 415             | 415    | 415    | 415    | 1       |
| protocolFee                                | 329             | 336    | 329    | 2329   | 257     |
| protocolFeeReceiver                        | 383             | 390    | 383    | 2383   | 257     |
| purchase                                   | 35764           | 145967 | 157577 | 250273 | 7589    |
| referralFeeSplit                           | 352             | 359    | 352    | 2352   | 281     |
| setProtocolFeeSettings                     | 24030           | 26291  | 26334  | 28411  | 512     |
| setProtocolFeeSplits                       | 23896           | 26585  | 24127  | 35549  | 768     |
| setSanctionsOracle                         | 47679           | 47679  | 47679  | 47679  | 1       |
| setWethAddress                             | 23796           | 24678  | 24678  | 25561  | 512     |
| transferOwnership                          | 23785           | 24868  | 24911  | 25810  | 512     |
| updateDropAllowance                        | 24303           | 63364  | 69944  | 75269  | 1282    |
| updateDropDecayRate                        | 24720           | 60725  | 61928  | 70413  | 1794    |
| updateDropDuration                         | 40471           | 60394  | 61643  | 93570  | 2048    |
| updateDropPayoutReceiver                   | 24657           | 65583  | 64064  | 77995  | 1539    |
| updateDropPresaleMerkleRoot                | 24291           | 65039  | 61934  | 87131  | 1538    |
| updateDropPrices                           | 24762           | 72094  | 70809  | 111521 | 1282    |
| weth                                       | 405             | 412    | 405    | 2405   | 257     |


| src/TLStacks721.sol:TLStacks721 contract |                 |        |        |          |         |
|------------------------------------------|-----------------|--------|--------|----------|---------|
| Deployment Cost                          | Deployment Size |        |        |          |         |
| 4199115                                  | 19518           |        |        |          |         |
| Function Name                            | min             | avg    | median | max      | # calls |
| closeDrop                                | 37677           | 71187  | 83964  | 88444    | 1026    |
| configureDrop                            | 26758           | 252826 | 246740 | 393686   | 5399    |
| freeMintFeeSplit                         | 350             | 357    | 350    | 2350     | 266     |
| getDrop                                  | 4020            | 4268   | 4264   | 4773     | 13851   |
| getDropPhase                             | 3204            | 3433   | 3204   | 28999    | 1681    |
| getDropRound                             | 587             | 590    | 587    | 2587     | 516     |
| getNumberMinted                          | 1030            | 2030   | 2030   | 3030     | 512     |
| owner                                    | 2376            | 2376   | 2376   | 2376     | 1       |
| pause                                    | 23742           | 25879  | 27995  | 28018    | 1025    |
| paused                                   | 348             | 348    | 348    | 348      | 1       |
| protocolFee                              | 351             | 358    | 351    | 2351     | 257     |
| protocolFeeReceiver                      | 427             | 434    | 427    | 2427     | 257     |
| purchase                                 | 35515           | 383829 | 222827 | 10942049 | 7543    |
| referralFeeSplit                         | 330             | 337    | 330    | 2330     | 266     |
| setProtocolFeeSettings                   | 24030           | 26295  | 26334  | 28411    | 512     |
| setProtocolFeeSplits                     | 23874           | 26340  | 24117  | 35527    | 768     |
| setSanctionsOracle                       | 47701           | 47701  | 47701  | 47701    | 1       |
| setWethAddress                           | 23752           | 24634  | 24634  | 25517    | 512     |
| transferOwnership                        | 23808           | 24895  | 24934  | 25833    | 512     |
| updateDropAllowance                      | 24187           | 65908  | 73352  | 78667    | 1282    |
| updateDropDecayRate                      | 24560           | 62983  | 64460  | 73777    | 1794    |
| updateDropDuration                       | 40359           | 62046  | 63866  | 96980    | 1797    |
| updateDropPayoutReceiver                 | 24430           | 68012  | 66529  | 81282    | 1539    |
| updateDropPresaleMerkleRoot              | 24132           | 67530  | 64467  | 90496    | 1538    |
| updateDropPrices                         | 24613           | 74586  | 74184  | 114908   | 1282    |
| weth                                     | 449             | 456    | 449    | 2449     | 257     |
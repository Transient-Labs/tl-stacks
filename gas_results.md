| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |        |        |        |         |
|------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |        |        |        |         |
| 3060744                                        | 15279           |        |        |        |         |
| Function Name                                  | min             | avg    | median | max    | # calls |
| bid                                            | 546             | 48354  | 29176  | 159526 | 67      |
| buyNow                                         | 593             | 32464  | 21583  | 120994 | 18      |
| calcNextMinBid                                 | 1243            | 3282   | 1348   | 7243   | 24      |
| calcProtocolFee                                | 753             | 2434   | 858    | 4858   | 34      |
| cancelAuction                                  | 6530            | 11424  | 8146   | 35898  | 7       |
| cancelSale                                     | 5976            | 9651   | 7212   | 26731  | 7       |
| configureAuction                               | 916             | 109133 | 121656 | 181366 | 32      |
| configureSale                                  | 850             | 62064  | 73254  | 131254 | 23      |
| getAuction                                     | 2356            | 2356   | 2356   | 2356   | 24      |
| getSale                                        | 1630            | 1630   | 1630   | 1630   | 10      |
| minBidIncreaseLimit                            | 353             | 1353   | 1353   | 2353   | 2       |
| minBidIncreasePerc                             | 396             | 1396   | 1396   | 2396   | 2       |
| owner                                          | 2376            | 2376   | 2376   | 2376   | 1       |
| pause                                          | 1603            | 3666   | 2550   | 6814   | 5       |
| paused                                         | 415             | 415    | 415    | 415    | 1       |
| protocolFeeLimit                               | 374             | 1374   | 1374   | 2374   | 2       |
| protocolFeePerc                                | 330             | 1330   | 1330   | 2330   | 2       |
| protocolFeeReceiver                            | 382             | 1382   | 1382   | 2382   | 2       |
| royaltyEngine                                  | 448             | 448    | 448    | 448    | 1       |
| setMinBidIncreaseSettings                      | 2554            | 5748   | 2581   | 12111  | 3       |
| setProtocolFeeSettings                         | 2624            | 7629   | 2654   | 17611  | 3       |
| setRoyaltyEngine                               | 2605            | 4159   | 4159   | 5713   | 2       |
| setSanctionsOracle                             | 26247           | 26247  | 26247  | 26247  | 1       |
| setWethAddress                                 | 2604            | 4158   | 4158   | 5712   | 2       |
| settleAuction                                  | 4818            | 53553  | 68793  | 80500  | 9       |
| transferOwnership                              | 2603            | 3501   | 3501   | 4400   | 2       |
| weth                                           | 404             | 1404   | 1404   | 2404   | 2       |


| src/TLStacks1155.sol:TLStacks1155 contract |                 |        |        |        |         |
|--------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                            | Deployment Size |        |        |        |         |
| 3344707                                    | 16854           |        |        |        |         |
| Function Name                              | min             | avg    | median | max    | # calls |
| closeDrop                                  | 7662            | 18118  | 22518  | 24118  | 6       |
| configureDrop                              | 652             | 151337 | 192626 | 272226 | 44      |
| getDrop                                    | 3208            | 3208   | 3208   | 3208   | 61      |
| getDropPhase                               | 2511            | 4430   | 2626   | 26479  | 14      |
| getDropRound                               | 705             | 2038   | 2705   | 2705   | 6       |
| getDrops                                   | 7063            | 7063   | 7063   | 7063   | 1       |
| getNumberMinted                            | 1220            | 2220   | 2220   | 3220   | 2       |
| owner                                      | 2420            | 2420   | 2420   | 2420   | 1       |
| pause                                      | 1603            | 3666   | 2550   | 6814   | 5       |
| paused                                     | 348             | 348    | 348    | 348    | 1       |
| protocolFee                                | 373             | 1373   | 1373   | 2373   | 2       |
| protocolFeeReceiver                        | 383             | 1383   | 1383   | 2383   | 2       |
| purchase                                   | 4765            | 61517  | 69158  | 143018 | 52      |
| setProtocolFeeSettings                     | 2581            | 6150   | 6150   | 9719   | 2       |
| setSanctionsOracle                         | 26291           | 26291  | 26291  | 26291  | 1       |
| setWethAddress                             | 2560            | 4130   | 4130   | 5700   | 2       |
| transferOwnership                          | 2603            | 3501   | 3501   | 4400   | 2       |
| updateDropAllowance                        | 635             | 12567  | 10533  | 39239  | 7       |
| updateDropDecayRate                        | 591             | 10695  | 7350   | 39195  | 9       |
| updateDropDuration                         | 7377            | 18436  | 8035   | 39273  | 8       |
| updateDropPayoutReceiver                   | 650             | 11520  | 8215   | 41453  | 9       |
| updateDropPresaleMerkleRoot                | 590             | 15315  | 10539  | 39194  | 7       |
| updateDropPrices                           | 734             | 18491  | 10944  | 50680  | 7       |
| weth                                       | 405             | 1405   | 1405   | 2405   | 2       |


| src/TLStacks721.sol:TLStacks721 contract |                 |        |        |         |         |
|------------------------------------------|-----------------|--------|--------|---------|---------|
| Deployment Cost                          | Deployment Size |        |        |         |         |
| 3650694                                  | 18382           |        |        |         |         |
| Function Name                            | min             | avg    | median | max     | # calls |
| closeDrop                                | 7560            | 18033  | 22424  | 24024   | 6       |
| configureDrop                            | 624             | 172142 | 216729 | 340975  | 45      |
| getDrop                                  | 3976            | 4225   | 4220   | 4505    | 64      |
| getDropPhase                             | 3182            | 5095   | 3216   | 28977   | 15      |
| getDropRound                             | 565             | 1898   | 2565   | 2565    | 6       |
| getNumberMinted                          | 1030            | 2030   | 2030   | 3030    | 2       |
| owner                                    | 2376            | 2376   | 2376   | 2376    | 1       |
| pause                                    | 1603            | 3666   | 2550   | 6814    | 5       |
| paused                                   | 393             | 393    | 393    | 393     | 1       |
| protocolFee                              | 373             | 1373   | 1373   | 2373    | 2       |
| protocolFeeReceiver                      | 405             | 1405   | 1405   | 2405    | 2       |
| purchase                                 | 4672            | 223059 | 114034 | 6563930 | 54      |
| setProtocolFeeSettings                   | 2604            | 6170   | 6170   | 9737    | 2       |
| setSanctionsOracle                       | 26269           | 26269  | 26269  | 26269   | 1       |
| setWethAddress                           | 2560            | 4130   | 4130   | 5700    | 2       |
| transferOwnership                        | 2581            | 3479   | 3479   | 4378    | 2       |
| updateDropAllowance                      | 615             | 13633  | 11927  | 41738   | 7       |
| updateDropDecayRate                      | 594             | 11517  | 8045   | 41717   | 9       |
| updateDropDuration                       | 7985            | 21117  | 8114   | 41752   | 7       |
| updateDropPayoutReceiver                 | 696             | 12509  | 8329   | 44018   | 9       |
| updateDropPresaleMerkleRoot              | 550             | 16385  | 11914  | 41673   | 7       |
| updateDropPrices                         | 658             | 19540  | 12385  | 52185   | 7       |
| weth                                     | 427             | 1427   | 1427   | 2427    | 2       |
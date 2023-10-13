# GAS

| src/TLAuctionHouse.sol:TLAuctionHouse contract |                 |        |        |        |         |
|------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |        |        |        |         |
| 3167646                                        | 15773           |        |        |        |         |
| Function Name                                  | min             | avg    | median | max    | # calls |
| bid                                            | 612             | 45280  | 18995  | 154335 | 57      |
| buyNow                                         | 659             | 29893  | 20715  | 123793 | 17      |
| calcNextMinBid                                 | 1243            | 3295   | 1348   | 7243   | 20      |
| calcProtocolFee                                | 753             | 2523   | 858    | 4858   | 28      |
| cancelAuction                                  | 6898            | 12403  | 8440   | 40766  | 7       |
| cancelSale                                     | 6344            | 10620  | 7507   | 31599  | 7       |
| configureAuction                               | 982             | 103863 | 122435 | 182145 | 28      |
| configureSale                                  | 916             | 62093  | 72033  | 132033 | 22      |
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
| setMinBidIncreaseSettings                      | 2594            | 7352   | 7352   | 12111  | 2       |
| setProtocolFeeSettings                         | 2664            | 10137  | 10137  | 17611  | 2       |
| setRoyaltyEngine                               | 2645            | 4179   | 4179   | 5713   | 2       |
| setSanctionsOracle                             | 26247           | 26247  | 26247  | 26247  | 1       |
| setWethAddress                                 | 2644            | 4178   | 4178   | 5712   | 2       |
| settleAuction                                  | 4818            | 46329  | 50377  | 81767  | 7       |
| transferOwnership                              | 2643            | 3521   | 3521   | 4400   | 2       |
| weth                                           | 404             | 1404   | 1404   | 2404   | 2       |


| src/TLStacks1155.sol:TLStacks1155 contract |                 |        |        |        |         |
|--------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                            | Deployment Size |        |        |        |         |
| 3330869                                    | 16745           |        |        |        |         |
| Function Name                              | min             | avg    | median | max    | # calls |
| closeDrop                                  | 5434            | 15894  | 20260  | 21860  | 6       |
| configureDrop                              | 718             | 154137 | 195289 | 274889 | 42      |
| getDrop                                    | 3208            | 3208   | 3208   | 3208   | 61      |
| getDropPhase                               | 2511            | 4537   | 2545   | 26479  | 13      |
| getDropRound                               | 705             | 1705   | 1705   | 2705   | 2       |
| getNumberMinted                            | 1220            | 2220   | 2220   | 3220   | 2       |
| owner                                      | 2420            | 2420   | 2420   | 2420   | 1       |
| pause                                      | 1603            | 3682   | 2590   | 6814   | 5       |
| paused                                     | 348             | 348    | 348    | 348    | 1       |
| protocolFee                                | 373             | 1373   | 1373   | 2373   | 2       |
| protocolFeeReceiver                        | 383             | 1383   | 1383   | 2383   | 2       |
| purchase                                   | 6765            | 64112  | 74158  | 144777 | 51      |
| setProtocolFeeSettings                     | 2621            | 6170   | 6170   | 9719   | 2       |
| setSanctionsOracle                         | 26291           | 26291  | 26291  | 26291  | 1       |
| setWethAddress                             | 2600            | 4150   | 4150   | 5700   | 2       |
| transferOwnership                          | 2643            | 3521   | 3521   | 4400   | 2       |
| updateDropAllowance                        | 701             | 12978  | 10273  | 39003  | 6       |
| updateDropDecayRate                        | 657             | 10132  | 5615   | 38959  | 7       |
| updateDropDuration                         | 4689            | 17628  | 17628  | 30567  | 2       |
| updateDropPayoutReceiver                   | 716             | 11839  | 10660  | 41217  | 7       |
| updateDropPresaleMerkleRoot                | 656             | 16193  | 11072  | 38958  | 6       |
| updateDropPrices                           | 800             | 19918  | 11631  | 50587  | 6       |
| weth                                       | 405             | 1405   | 1405   | 2405   | 2       |


| src/TLStacks721.sol:TLStacks721 contract |                 |        |        |         |         |
|------------------------------------------|-----------------|--------|--------|---------|---------|
| Deployment Cost                          | Deployment Size |        |        |         |         |
| 3929626                                  | 19735           |        |        |         |         |
| Function Name                            | min             | avg    | median | max     | # calls |
| closeDrop                                | 5368            | 15738  | 20082  | 21682   | 6       |
| configureDrop                            | 678             | 174016 | 219192 | 303835  | 42      |
| getDrop                                  | 3892            | 4136   | 4136   | 4421    | 58      |
| getDropPhase                             | 3134            | 5184   | 3249   | 28929   | 14      |
| getDropRound                             | 541             | 1541   | 1541   | 2541    | 2       |
| getNumberMinted                          | 994             | 1994   | 1994   | 2994    | 2       |
| owner                                    | 2352            | 2352   | 2352   | 2352    | 1       |
| pause                                    | 1584            | 3664   | 2578   | 6790    | 5       |
| paused                                   | 393             | 393    | 393    | 393     | 1       |
| protocolFee                              | 373             | 1373   | 1373   | 2373    | 2       |
| protocolFeeReceiver                      | 381             | 1381   | 1381   | 2381    | 2       |
| purchase                                 | 6624            | 298278 | 106532 | 9357652 | 48      |
| setProtocolFeeSettings                   | 2620            | 6164   | 6164   | 9708    | 2       |
| setSanctionsOracle                       | 26233           | 26233  | 26233  | 26233   | 1       |
| setWethAddress                           | 2576            | 4124   | 4124   | 5672    | 2       |
| transferOwnership                        | 2597            | 3463   | 3463   | 4330    | 2       |
| updateDropAllowance                      | 669             | 14092  | 11719  | 41423   | 6       |
| updateDropDecayRate                      | 648             | 10952  | 5573   | 41402   | 7       |
| updateDropDuration                       | 5262            | 18630  | 18630  | 31999   | 2       |
| updateDropPayoutReceiver                 | 738             | 12831  | 12148  | 43679   | 7       |
| updateDropPresaleMerkleRoot              | 604             | 17288  | 12510  | 41358   | 6       |
| updateDropPrices                         | 700             | 20964  | 13021  | 51965   | 6       |
| weth                                     | 403             | 1403   | 1403   | 2403    | 2       |

# COVERAGE

| File                     | % Lines          | % Statements     | % Branches       | % Funcs         |
|--------------------------|------------------|------------------|------------------|-----------------|
| script/Deployments.s.sol | 0.00% (0/6)      | 0.00% (0/6)      | 100.00% (0/0)    | 0.00% (0/3)     |
| src/TLAuctionHouse.sol   | 99.36% (156/157) | 97.42% (227/233) | 93.33% (84/90)   | 100.00% (25/25) |
| src/TLStacks1155.sol     | 97.42% (151/155) | 96.36% (212/220) | 97.73% (86/88)   | 96.43% (27/28)  |
| src/TLStacks721.sol      | 99.33% (149/150) | 98.60% (211/214) | 97.73% (86/88)   | 100.00% (27/27) |
| Total                    | 97.44% (456/468) | 96.58% (650/673) | 96.24% (256/266) | 95.18% (79/83)  |

Uncovered for src/TLAuctionHouse.sol:
- Branch (branch: 9, path: 0) (location: source ID 82, line 252, chars 10568-11317, hits: 0)
- Branch (branch: 13, path: 0) (location: source ID 82, line 267, chars 11237-11306, hits: 0)
- Statement (location: source ID 82, line 267, chars 11280-11306, hits: 0)
- Branch (branch: 26, path: 0) (location: source ID 82, line 346, chars 14585-14662, hits: 0)
- Statement (location: source ID 82, line 346, chars 14636-14662, hits: 0)
- Branch (branch: 39, path: 0) (location: source ID 82, line 474, chars 19698-19764, hits: 0)
- Statement (location: source ID 82, line 474, chars 19738-19764, hits: 0)
- Branch (branch: 40, path: 0) (location: source ID 82, line 522, chars 21986-22048, hits: 0)
- Statement (location: source ID 82, line 522, chars 22021-22048, hits: 0)
- Branch (branch: 41, path: 0) (location: source ID 82, line 539, chars 22702-22761, hits: 0)
- Statement (location: source ID 82, line 539, chars 22734-22761, hits: 0)
- Line (location: source ID 82, line 597, chars 25226-25236, hits: 0)
- Statement (location: source ID 82, line 597, chars 25226-25236, hits: 0)

Uncovered for src/TLStacks1155.sol:
- Branch (branch: 15, path: 0) (location: source ID 83, line 230, chars 10464-10516, hits: 0)
- Statement (location: source ID 83, line 230, chars 10495-10516, hits: 0)
- Branch (branch: 16, path: 0) (location: source ID 83, line 232, chars 10582-10661, hits: 0)
- Statement (location: source ID 83, line 232, chars 10635-10661, hits: 0)
- Function "getDrops" (location: source ID 83, line 468, chars 21264-21549, hits: 0)
- Line (location: source ID 83, line 469, chars 21385-21420, hits: 0)
- Statement (location: source ID 83, line 469, chars 21385-21420, hits: 0)
- Line (location: source ID 83, line 470, chars 21435-21448, hits: 0)
- Statement (location: source ID 83, line 470, chars 21435-21448, hits: 0)
- Statement (location: source ID 83, line 470, chars 21450-21469, hits: 0)
- Statement (location: source ID 83, line 470, chars 21471-21474, hits: 0)
- Line (location: source ID 83, line 471, chars 21490-21532, hits: 0)
- Statement (location: source ID 83, line 471, chars 21490-21532, hits: 0)
- Line (location: source ID 83, line 584, chars 26668-26688, hits: 0)
- Statement (location: source ID 83, line 584, chars 26668-26688, hits: 0)

Uncovered for src/TLStacks721.sol:
- Branch (branch: 15, path: 0) (location: source ID 84, line 216, chars 9853-9905, hits: 0)
- Statement (location: source ID 84, line 216, chars 9884-9905, hits: 0)
- Branch (branch: 16, path: 0) (location: source ID 84, line 218, chars 9962-10041, hits: 0)
- Statement (location: source ID 84, line 218, chars 10015-10041, hits: 0)
- Line (location: source ID 84, line 545, chars 24706-24726, hits: 0)
- Statement (location: source ID 84, line 545, chars 24706-24726, hits: 0)
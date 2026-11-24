# Burner Loans lifecycle after governance

The actual OCG proposal runs in the shared mainnet fixture before each case. These tests exercise
real vault custody, deposits, borrowing, extension, repayment, withdrawal, default/seizure,
inventory funding and yield distribution with the unmodified OCG launch configuration. OHM uses 9 decimals;
collateral assets use 18 decimals. External feed timestamps are adapted across governance.

| ID | Initial state / caller | Execution and authoritative effects | Test |
| --- | --- | --- | --- |
| BLPF-P02 | Launched USDS market; borrower | Deposit, borrow, extend, partial and full repay, withdraw; previews agree, token deltas and FLOAN/Core/Inventory/custody liabilities reconcile | Covered: [test][test_givenLaunchedUsds_whenBorrowerServicesLoan] |
| BLPF-P03 | Launched USDe market; borrower | Same servicing sequence; final withdrawal returns real sUSDe shares without synchronous redemption | Covered: [test][test_givenLaunchedUsde_whenBorrowerServicesLoan] |
| BLPF-P04 | Empty inventory; DAO provider authorized by OCG | Provider supplies OHM, borrower uses idle liquidity plus minted shortfall; repay restores provider claim and burns only minted excess | Covered: [test][test_givenProviderSuppliedOhm_whenBorrowerUsesMintedShortfall] |
| BLPF-P05 | Expired USDS / USDe debt; keeper | Seize both positions; actual output-token allocations reach keeper and Treasury, principal and custody liabilities close | Covered: [test][test_givenExpiredLoans_whenKeeperSeizesBothMarkets] |
| BLPF-P06 | Real vault deposits; Heart | Zero-yield and controlled positive-yield task runs preserve liabilities and route actual output through RevenueDistributor to Treasury; full Heart beat retains prior tasks/order | Covered: [test][test_givenVaultYield_whenHeartTasksRun] |
| BLPF-P08 | Expired USDS debt; Heart calls SeizerTask | Actual task defaults the position, clears Inventory principal and routes collateral to Treasury without a keeper reward | Covered: [test][test_givenExpiredPosition_whenHeartSeizerTaskRuns] |
| BLPF-P09 | Empty OHM/USDS and OHM/USDe cache; PriceCacherTask added at the front of Heart in the fork; 2,500,000 task gas and 1,200,000 gas per pair | Both pairs advance from round zero to one and Heart finishes the beat | Covered: [test][test_givenLaunchedMarkets_whenPriceCacherRunsInHeart_thenRefreshesBothPairs] |
| BLPF-T02 | Same pair list; 1,000,000 task gas and 400,000 gas per pair | Both pairs emit `PairCacheFailed` with a zero selector. Neither cache round advances and Heart still finishes the beat | Covered: [test][test_whenPairGasIsTooLow_thenHeartCompletesWithoutRefreshing] |

The PriceCacherTask cases use mainnet block 25,973,712 and the inherited proposal
fixture's feed timestamp adapters. Under the deployment compiler profile, the passing
test measured 726,203 gas for OHM/USDS, 808,168 gas for OHM/USDe, and 3,573,228 gas
for the full beat. This measures the two configured pairs at that block.

[test_givenLaunchedUsds_whenBorrowerServicesLoan]: ./lifecycleFork.t.sol#L28
[test_givenLaunchedUsde_whenBorrowerServicesLoan]: ./lifecycleFork.t.sol#L33
[test_givenProviderSuppliedOhm_whenBorrowerUsesMintedShortfall]: ./lifecycleFork.t.sol#L38
[test_givenExpiredLoans_whenKeeperSeizesBothMarkets]: ./lifecycleFork.t.sol#L95
[test_givenVaultYield_whenHeartTasksRun]: ./lifecycleFork.t.sol#L107
[test_givenExpiredPosition_whenHeartSeizerTaskRuns]: ./lifecycleFork.t.sol#L202
[test_givenLaunchedMarkets_whenPriceCacherRunsInHeart_thenRefreshesBothPairs]: ./priceCacherFork.t.sol#L16
[test_whenPairGasIsTooLow_thenHeartCompletesWithoutRefreshing]: ./priceCacherFork.t.sol#L32

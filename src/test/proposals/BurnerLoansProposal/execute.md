# Burner Loans governance execution on mainnet

Implementation: [BurnerLoansProposal.t.sol](../BurnerLoansProposal.t.sol), in
`test_givenPreparedMainnet_whenGovernanceExecutes`. The suite executes governance through
the shared [BurnerLoansForkTest fixture](./fixtures/BurnerLoansForkTest.sol).

The shared fixture deploys the production sequences, leaves the backing oracle uninitialized and prepares
Kernel membership before executing the actual Governor proposal at mainnet block 25,973,712.
PRICE, Heart, tokens and vaults retain their real code and version metadata. External feed
publication timestamps are adapted across the voting period. No custody market or launch role is
seeded before governance. OCG admits USDe, configures both vault pairs on shared DepositManager
v1.1, assigns roles, installs Core-bound Auth exactly once and launches the lending graph.

| ID | Initial state / caller | Execution and effects | Test |
| --- | --- | --- | --- |
| BLPF-P01 | USDe unapproved; prepared disabled graph; OCG | Initialize BackingOracle to $11.99, select/enable its queue, admit USDe through active PriceConfig, configure both custody routes and markets, select Auth exactly once, enable graph and remove helper ADMIN; verify all six timelocks are deployed, Kernel-active, target-bound, selected and enabled; verify all four DAO operational roles; preserve existing OHM/USDS PRICE data | Covered: [test][test_givenPreparedMainnet_whenGovernanceExecutes] |
| BLPF-P09 | Launched three-feed USDe configuration; any one source unavailable | Two remaining sources still return a price within $0.99–$1.01 | Covered: [test][test_givenOneUsdeFeedUnavailable_whenPriceRead] |
| BLPF-P10 | Launched three-feed USDe configuration; only one source available | Strict aggregation rejects the price with the exact insufficient-feed error | Covered: [test][test_givenOnlyOneUsdeFeedAvailable_whenPriceRead_reverts] |
| BLPF-P11 | Launched three-feed USDe configuration; two sources report $1 and any one reports $2 | Exclude the outlier and return exactly $1 at 18 decimals | Covered: [test][test_givenOneUsdeFeedDeviates_whenPriceRead] |

Borrower operations are covered separately in [post-launch lifecycle](./lifecycleFork.md).

[test_givenPreparedMainnet_whenGovernanceExecutes]: ../BurnerLoansProposal.t.sol#L108
[test_givenOneUsdeFeedUnavailable_whenPriceRead]: ../BurnerLoansProposal.t.sol#L36
[test_givenOnlyOneUsdeFeedAvailable_whenPriceRead_reverts]: ../BurnerLoansProposal.t.sol#L56
[test_givenOneUsdeFeedDeviates_whenPriceRead]: ../BurnerLoansProposal.t.sol#L86

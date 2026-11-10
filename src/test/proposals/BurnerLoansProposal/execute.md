# Burner Loans governance execution on mainnet

The shared fixture deploys the production sequences, populates the backing oracle and prepares
Kernel membership before executing the actual Governor proposal at mainnet block 25,973,712.
PRICE, Heart, tokens and vaults retain their real code and version metadata. External feed
publication timestamps are adapted across the voting period. No custody market or launch role is
seeded before governance. OCG admits USDe, configures both vault pairs on shared DepositManager
v1.1, assigns roles, installs Core-bound Auth exactly once and launches the lending graph.

| ID | Initial state / caller | Execution and effects | Test |
| --- | --- | --- | --- |
| BLPF-P01 | USDe unapproved; prepared disabled graph; OCG | Admit USDe through active PriceConfig, configure both custody routes and markets, select Auth exactly once, enable graph and remove helper ADMIN; verify all six timelocks are deployed, Kernel-active, target-bound, selected and enabled; verify all four DAO operational roles; preserve existing OHM/USDS PRICE data | Covered: [test][test_givenPreparedMainnet_whenGovernanceExecutes] |

Borrower operations are covered separately in [post-launch lifecycle](./lifecycleFork.md).

[test_givenPreparedMainnet_whenGovernanceExecutes]: ../BurnerLoansProposal.t.sol#L28

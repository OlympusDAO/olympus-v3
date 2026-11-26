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

Controller and role acceptance below use the real Governor fixture without pre-granting the
custody proposer role or selecting its queue during setup. Governance supplies both launch effects. The action-budget fixture must retain the operational Heart role, include the
exact custody-role grant and final helper ADMIN revocation, and stay within 15 actions.

| ID | Initial state / caller | Execution and effects | Test |
| --- | --- | --- | --- |
| BLPF-P01 | USDe unapproved; prepared disabled graph; OCG | Initialize BackingOracle to $11.99, select/enable its queue, admit USDe through active PriceConfig, configure both custody routes and markets, select Auth exactly once, enable graph and remove helper ADMIN; verify all seven timelocks are deployed, Kernel-active, target-bound, selected and enabled; verify all five DAO operational roles, including the exact custody proposer grant with no DAO/helper ADMIN; preserve existing OHM/USDS PRICE data | Covered: [test][test_givenPreparedMainnet_whenGovernanceExecutes] |
| BLPF-P09 | Launched three-feed USDe configuration; any one source unavailable | Two remaining sources still return a price within $0.99–$1.01 | Covered: [test][test_givenOneUsdeFeedUnavailable_whenPriceRead] |
| BLPF-P10 | Launched three-feed USDe configuration; only one source available | Strict aggregation rejects the price with the exact insufficient-feed error | Covered: [test][test_givenOnlyOneUsdeFeedAvailable_whenPriceRead_reverts] |
| BLPF-P11 | Launched three-feed USDe configuration; two sources report $1 and any one reports $2 | Exclude the outlier and return exactly $1 at 18 decimals | Covered: [test][test_givenOneUsdeFeedDeviates_whenPriceRead] |
| BLPF-D01 | DAO; fuzz execution caller; Real launched manager/queue | Exact Kernel/target, active/enabled selected queue; delay then authoritative cap change without custody delta | Covered: [operation][test_givenGovernanceLaunch_whenDaoQueuesDepositCap_executes] |
| BLPF-P12 | Fuzz distribution caller; No compatible deployed YRF V2 | All four new receipts reach actual TRSRY; zero recipient and repurchase BPS | Covered: [Treasury][test_givenGovernanceLaunch_whenRevenueDistributed_allReceiptsReachTreasury] |
| BLPF-T01 | Real OCG; Inject late launch/queue failure | Whole proposal including temporary ADMIN and permanent grants rolls back; restored prerequisites permit retry | Covered: [whole OCG][test_givenLateLaunchFailure_whenGovernanceExecutes_rollsBackBindingsAndRoles] |
| BLPF-N01 | Real Governor; Supported fork preparation | Actual action list at most 15; exact new role grant; final temporary revocation | Covered: [actions][test_givenGovernanceLaunch_whenActionsRead_includesCustodyGrantWithinLimit], [worst role absence][test_givenOnlyHeartRolePresent_whenActionsBuilt_fitsWorstCaseBudget], [missing Heart role][test_givenHeartRoleMissing_whenActionsBuilt_reverts] |
| BLPF-A02 | Fuzz caller excluding every ADMIN holder; explicit DAO seed; Active/enabled launched manager | Direct controller replacement rejects ROLES_RequireRole(ADMIN_ROLE), pointer unchanged | Covered: [fuzz][test_givenGovernanceLaunch_whenNonAdminReplacesController_reverts], [DAO][test_givenGovernanceLaunch_whenDaoReplacesController_reverts] |
| BLPF-D02 | Launched queue replaced by ADMIN; target/queue paused | ADMIN direct configuration remains available before pause; emergency cancels the old action and releases its key without readiness reads | Covered: [repair/cancel][test_givenGovernanceLaunch_whenControllerReplacedAndPaused_adminRepairAndEmergencyCancellationRemain] |

Borrower operations are covered separately in [post-launch lifecycle](./lifecycleFork.md).

[test_givenPreparedMainnet_whenGovernanceExecutes]: ../BurnerLoansProposal.t.sol#L117
[test_givenOneUsdeFeedUnavailable_whenPriceRead]: ../BurnerLoansProposal.t.sol#L45
[test_givenOnlyOneUsdeFeedAvailable_whenPriceRead_reverts]: ../BurnerLoansProposal.t.sol#L65
[test_givenOneUsdeFeedDeviates_whenPriceRead]: ../BurnerLoansProposal.t.sol#L95

[test_givenGovernanceLaunch_whenDaoQueuesDepositCap_executes]: ../BurnerLoansProposal.t.sol#L457
[test_givenGovernanceLaunch_whenRevenueDistributed_allReceiptsReachTreasury]: ../BurnerLoansProposal.t.sol#L528

[test_givenGovernanceLaunch_whenActionsRead_includesCustodyGrantWithinLimit]: ../BurnerLoansProposal.t.sol#L367
[test_givenGovernanceLaunch_whenNonAdminReplacesController_reverts]: ../BurnerLoansProposal.t.sol#L436
[test_givenGovernanceLaunch_whenDaoReplacesController_reverts]: ../BurnerLoansProposal.t.sol#L452

[test_givenGovernanceLaunch_whenControllerReplacedAndPaused_adminRepairAndEmergencyCancellationRemain]: ../BurnerLoansProposal.t.sol#L489

[test_givenOnlyHeartRolePresent_whenActionsBuilt_fitsWorstCaseBudget]: ../BurnerLoansProposal.t.sol#L393

[test_givenHeartRoleMissing_whenActionsBuilt_reverts]: ../BurnerLoansProposal.t.sol#L419

[test_givenLateLaunchFailure_whenGovernanceExecutes_rollsBackBindingsAndRoles]: ./heartOrderFork.t.sol#L32

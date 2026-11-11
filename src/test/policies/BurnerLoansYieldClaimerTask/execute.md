# BurnerLoansYieldClaimerTask.execute coverage plan

Source: [execute](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L150). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-EXECUTE` identifies this contract/function.

Scheduler admission: execute rejects own Kernel inactivity with BurnerLoans_PolicyNotActive(task) before authenticating HEART_ROLE, including while locally disabled. An active, authorized but disabled task returns before its self-call. No business action, cursor progress or events are committed on either path.

Own Kernel activity precedes HEART authorization and the disabled no-op; Core gates are checked in the self-task. Bounded task gas, four-byte copied errors.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Task defaults execution budget constructor-selected; minimumGasToAttempt250000; gasReserve100000; pre-cursor buffer50000. Loop visits <=assetCount attempts; stop if gasleft<=minimum or after asset lookup gasleft<=reserve+50000, without advancing current cursor. Advance cursor BEFORE bounded claim attempt so caught per-asset failure/OOG does not strand traversal. Copies at most4bytes per failure. A later unbounded registry read failure propagates through selftask and rolls back earlier claims/cursor from that selftask; outer execute reports it.

## Authorization

ROLES initialized. Unauthorized calls have no downstream reads or effects. The authorized row uses ready dependencies and asserts the successful claim effects.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-EXECUTE-A01 | Fuzz caller without HEART_ROLE; exclude every HEART_ROLE holder | Task active; locally enabled/disabled | ROLES_RequireRole(HEART_ROLE) | Covered: [test][test_givenCallerWithoutHeartRole_reverts], [test][test_givenDisabled_whenCallerWithoutHeartRole_reverts] |
| BLYC-EXECUTE-A02 | Fuzz HEART_ROLE holder | Task/Core active and enabled; registered asset with positive yield; task settlement role present; sufficient gas | Caller admitted; successful bounded claim with exact yield routing and cursor advance | Covered: [test][test_givenMultipleYieldAssets_whenHeartExecutes] |

## Lifecycle

HEART_ROLE holder; ROLES retained after deactivation. Nonempty compatible registry, positive claimable yield, sufficient execution gas, compatible Custody and own yield-claimer role. All active+enabled components execute one successful claim. When an earlier lifecycle gate returns, configure the next read to revert and prove it is never reached. Own and Core states vary independently.

| ID | Caller | Task Kernel active | Task enabled | Core Kernel active | Core enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-EXECUTE-L01 | HEART_ROLE holder | true | true | true | true | Claim succeeds | One claim, exact yield routing and cursor advance | Covered: [test][test_givenMultipleYieldAssets_whenHeartExecutes] |
| BLYC-EXECUTE-L02 | HEART_ROLE holder | true | true | true | false | Self-task returns before registry read | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenCoreDisabled_whenExecuted], [test][test_givenBurnerLoansDisabled_executeDoesNotQueryRegistry] |
| BLYC-EXECUTE-L03 | HEART_ROLE holder | true | true | false | true | Self-task returns before registry read | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenBurnerLoansInactive_executeDoesNotQueryRegistry] |
| BLYC-EXECUTE-L04 | HEART_ROLE holder | true | true | false | false | Self-task returns before registry read | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenBurnerLoansInactive_executeDoesNotQueryRegistry] |
| BLYC-EXECUTE-L05 | HEART_ROLE holder | true | false | true | true | Return before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenDisabled_isNoOpBeforeRegistryRead] |
| BLYC-EXECUTE-L06 | HEART_ROLE holder | true | false | true | false | Return before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenDisabled_isNoOpBeforeRegistryRead] |
| BLYC-EXECUTE-L07 | HEART_ROLE holder | true | false | false | true | Return before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenDisabled_isNoOpBeforeRegistryRead] |
| BLYC-EXECUTE-L08 | HEART_ROLE holder | true | false | false | false | Return before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenDisabled_isNoOpBeforeRegistryRead] |
| BLYC-EXECUTE-L09 | HEART_ROLE holder | false | true | true | true | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLYC-EXECUTE-L10 | HEART_ROLE holder | false | true | true | false | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |
| BLYC-EXECUTE-L11 | HEART_ROLE holder | false | true | false | true | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |
| BLYC-EXECUTE-L12 | HEART_ROLE holder | false | true | false | false | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |
| BLYC-EXECUTE-L13 | HEART_ROLE holder | false | false | true | true | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLYC-EXECUTE-L14 | HEART_ROLE holder | false | false | true | false | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |
| BLYC-EXECUTE-L15 | HEART_ROLE holder | false | false | false | true | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |
| BLYC-EXECUTE-L16 | HEART_ROLE holder | false | false | false | false | BurnerLoans_PolicyNotActive(task) before self-call | Cursor, payouts and balances unchanged; no lifecycle/failure events | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-EXECUTE-P01 | HEART | All claims succeed; one/multiple assets; selected start and wraparound | Bounded iteration, preserve circular progress | Every attemptedasset once per beat at most | Covered: [test][test_givenMultipleYieldAssets_whenHeartExecutes], [test][test_givenClaimSucceeds_callsBurnerLoans], [test][test_givenMultipleClaimsSucceed_claimsEveryAsset], [test][test_givenSelectedCursor_executesInCircularOrder], [test][test_givenCursorOutOfRangeAfterRegistryShrink_normalizesTraversal], [test][test_givenCallerIsSelf_executesTask] |
| BLYC-EXECUTE-P02 | HEART | Oneclaim reverts/exhausts gas; laterclaim succeeds | YieldAssetClaimFailed, laterasset still processed | Earlier claims and cursor progress committed; resumes after failedasset | Covered: [test][test_givenFirstClaimReverts_whenLaterAssetIsClaimed], [test][test_givenClaimReverts_reportsFailure], [test][test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix], [test][test_givenClaimRevertsWithLargeData_reportsBoundedFailure], [test][test_givenClaimExhaustsGas_laterHeartTaskStillExecutes], [test][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes], [test][test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute] |
| BLYC-EXECUTE-P03 | HEART | Selftask budget1; registry read failure including laterlookup | ExecutionFailed bounded prefix | Entire selftask claim/cursor state rollback; later Heart task still executes | Covered: [test][test_givenInsufficientPeriodicBudget_whenClaimedDirectly], [test][test_givenMinimumTaskGasLimit_reportsExecutionFailure], [test][test_givenAssetRegistryReadReverts_reportsExecutionFailure], [test][test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor], [test][test_givenSelfTaskShortError_whenExecuted], [test][test_givenSelfTaskLargeError_whenExecuted] |

## Shared assertions

Reuse existing gas-burning target and later Heart task fixture. A failing individual claim and failing registry lookup have different rollback scopes; they must have distinct tests, not a general catch-all failure row.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Scheduler regressions

Reuse first/middle gas-burning claim preserving earlier progress and resuming after bad asset; postlookup reserve threshold; short/oversized error prefixes; later registry read reverting all prior selftask claims; minimum budget and registry shrink; direct claim still available when periodic gas budget insufficient.

[test_givenAssetRegistryReadReverts_reportsExecutionFailure]: execute.t.sol#L428
[test_givenBurnerLoansDisabled_executeDoesNotQueryRegistry]: execute.t.sol#L186
[test_givenBurnerLoansInactive_executeDoesNotQueryRegistry]: execute.t.sol#L200
[test_givenCallerIsSelf_executesTask]: selfExecuteTask.t.sol#L50
[test_givenCallerWithoutHeartRole_reverts]: execute.t.sol#L45
[test_givenClaimExhaustsGas_laterHeartTaskStillExecutes]: execute.t.sol#L313
[test_givenClaimRevertsWithLargeData_reportsBoundedFailure]: execute.t.sol#L261
[test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix]: execute.t.sol#L246
[test_givenClaimReverts_reportsFailure]: execute.t.sol#L230
[test_givenClaimSucceeds_callsBurnerLoans]: execute.t.sol#L59
[test_givenCoreDisabled_whenExecuted]: executeIntegration.t.sol#L21
[test_givenCursorOutOfRangeAfterRegistryShrink_normalizesTraversal]: execute.t.sol#L111
[test_givenDisabled_isNoOpBeforeRegistryRead]: execute.t.sol#L142
[test_givenDisabled_whenCallerWithoutHeartRole_reverts]: execute.t.sol#L216
[test_givenFirstClaimReverts_whenLaterAssetIsClaimed]: executeIntegration.t.sol#L94
[test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute]: execute.t.sol#L486
[test_givenInsufficientPeriodicBudget_whenClaimedDirectly]: executeIntegration.t.sol#L38
[test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor]: execute.t.sol#L444
[test_givenLaterClaimExhaustsGas_preservesProgressAndResumes]: execute.t.sol#L340
[test_givenMinimumTaskGasLimit_reportsExecutionFailure]: execute.t.sol#L370
[test_givenMultipleClaimsSucceed_claimsEveryAsset]: execute.t.sol#L71
[test_givenMultipleYieldAssets_whenHeartExecutes]: executeIntegration.t.sol#L57
[test_givenSelectedCursor_executesInCircularOrder]: execute.t.sol#L92
[test_givenSelfTaskLargeError_whenExecuted]: execute.t.sol#L473
[test_givenSelfTaskShortError_whenExecuted]: execute.t.sol#L463
[test_givenTaskInactive_whenExecuted_reverts]: execute.t.sol#L156

[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: execute.t.sol#L504

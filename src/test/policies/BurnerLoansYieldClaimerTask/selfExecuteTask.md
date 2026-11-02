# BurnerLoansYieldClaimerTask.selfExecuteTask coverage plan

Source: [selfExecuteTask](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L167). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-SELF-EXECUTE` identifies this contract/function.

Only self; unbounded number of registered assets bounded by gas and one pass. Core registry count may shrink between administrative beats; next index normalized modulo count.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Task defaults execution budget constructor-selected; minimumGasToAttempt250000; gasReserve100000; pre-cursor buffer50000. Loop visits <=assetCount attempts; stop if gasleft<=minimum or after asset lookup gasleft<=reserve+50000, without advancing current cursor. Advance cursor BEFORE bounded claim attempt so caught per-asset failure/OOG does not strand traversal. Copies at most4bytes per failure. A later unbounded registry read failure propagates through selftask and rolls back earlier claims/cursor from that selftask; outer execute reports it.

## Authorization

Any caller except this contract is rejected before lifecycle, registry or gas-dependent work. Fuzz callers including EOAs, ADMIN/HEART role holders and sibling policies, excluding only self.

| ID | Caller | Inputs / competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-SELF-EXECUTE-A01 | Fuzz caller excluding address(BurnerLoansYieldClaimerTask), including all role-holder classes | Any role/lifecycle | OnlySelf | Unchanged | Covered: [test][test_whenExternalCallerExecutesTaskDirectly_reverts], [test][test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts] |
| BLYC-SELF-EXECUTE-A02 | This Task through the gas-bounded execute self-call | Own task active/enabled; Core ready; empty registered-asset list | Caller admitted; successful empty scan | Cursor, balances and lifecycle unchanged; no claim or failure event | Covered: [test][test_givenNoRegisteredAssets_isNoOp], [test][test_givenEmptyRegistry_whenHeartSelfCalls] |

## Lifecycle

Caller is this contract; own task enabled/active state is not checked by this direct self entry. Seed a nonzero prior cursor and reverting registry lookup to prove Core gates return before registry reads. ROLES is irrelevant to this self-only entry.

| ID | Caller | Core Kernel active | Core enabled | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-SELF-EXECUTE-L01 | Self | false | true | Return before registry reads | Cursor and payouts unchanged; no events | Covered: [test][test_givenUnavailableCore_whenSelfCalled] |
| BLYC-SELF-EXECUTE-L02 | Self | true | false | Return before registry reads | Cursor and payouts unchanged; no events | Covered: [test][test_givenUnavailableCore_whenSelfCalled] |
| BLYC-SELF-EXECUTE-L03 | Self | false | false | Return before registry reads | Cursor and payouts unchanged; no events | Covered: [test][test_givenUnavailableCore_whenSelfCalled] |

## Registry inputs

Core active and enabled; caller=self. Registry count is distinct from lifecycle availability.

| ID | Caller | Asset count | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-SELF-EXECUTE-I01 | Self | 0 | Return after getAssetCount; no getAssetAt call | Cursor and payouts unchanged; no events | Covered: [test][test_givenNoRegisteredAssets_isNoOp], [test][test_givenEmptyRegistry_whenHeartSelfCalls] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-SELF-EXECUTE-P01 | Self | Later registry getAssetAt reverts after earlier successfulclaim | Propagated selftask revert | All selftask effects rollback, including earlierclaim/cursor | Covered: [test][test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor], [test][test_givenLaterRegistryFailure_whenSelfCalled_reverts] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-SELF-EXECUTE-P02 | Self | Forwarded self-call budgets at the measured attempt and postlookup reserve breakpoints−1, exact, +1 | Stop at/below threshold; advance only when attempting claim | No skipped current asset before attempt | Covered: [test][test_givenAttemptThresholdExceedsAvailableGas_pausesBeforeLookup], [test][test_givenPostLookupGasCannotPreserveReserve_pausesBeforeCursorAdvance], [test][test_givenAttemptGasBreakpoint_whenBudgetIsAdjacent], [test][test_givenPostLookupReserveBreakpoint_whenBudgetIsAdjacent] |
| BLYC-SELF-EXECUTE-P03 | Self | Failed or gas-burning claim at first/middle/last | Per-asset catch, cursor already next | Earlier payments stay committed; laterassets reached on repeated beats | Covered: [test][test_givenClaimReverts_reportsFailure], [test][test_givenClaimExhaustsGas_laterHeartTaskStillExecutes], [test][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes], [test][test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute] |
| BLYC-SELF-EXECUTE-P04 | Self | Three+ assets, lowbudget repeatedbeats; single permanently failingasset | Live assets continue progressing | No starvation; exactly bounded calldata/output copy | Covered: [test][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes], [test][test_givenLimitedExecutionGas_repeatedBeatsReachEveryAsset], [test][test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute] |

Gas boundary tests calibrate the first sufficient forwarded budget for this compiler after warming the same reads. They assert adjacent-budget cursor behavior without adding production instrumentation.

Gas boundary tests calibrate the first sufficient forwarded budget for this compiler after warming the same reads. They assert adjacent-budget cursor behavior without adding production instrumentation.

Gas boundary tests calibrate the first sufficient forwarded budget for this compiler after warming the same reads. They assert adjacent-budget cursor behavior without adding production instrumentation.

Gas boundary tests calibrate the first sufficient forwarded budget for this compiler after warming the same reads. They assert adjacent-budget cursor behavior without adding production instrumentation.

Co-located API assertions: `nextAssetIndex`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenAttemptGasBreakpoint_whenBudgetIsAdjacent]: selfExecuteTask.t.sol#L93
[test_givenAttemptThresholdExceedsAvailableGas_pausesBeforeLookup]: execute.t.sol#L273
[test_givenClaimExhaustsGas_laterHeartTaskStillExecutes]: execute.t.sol#L313
[test_givenClaimReverts_reportsFailure]: execute.t.sol#L230
[test_givenEmptyRegistry_whenHeartSelfCalls]: selfExecuteTask.t.sol#L83
[test_givenGasBurnerAtLastAsset_whenRepeatedBeatsExecute]: execute.t.sol#L486
[test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor]: execute.t.sol#L444
[test_givenLaterClaimExhaustsGas_preservesProgressAndResumes]: execute.t.sol#L340
[test_givenLaterRegistryFailure_whenSelfCalled_reverts]: selfExecuteTask.t.sol#L155
[test_givenLimitedExecutionGas_repeatedBeatsReachEveryAsset]: execute.t.sol#L402
[test_givenNoRegisteredAssets_isNoOp]: execute.t.sol#L389
[test_givenPostLookupGasCannotPreserveReserve_pausesBeforeCursorAdvance]: execute.t.sol#L293
[test_givenPostLookupReserveBreakpoint_whenBudgetIsAdjacent]: selfExecuteTask.t.sol#L98
[test_givenUnavailableCore_whenSelfCalled]: selfExecuteTask.t.sol#L64
[test_whenExternalCallerExecutesTaskDirectly_reverts]: selfExecuteTask.t.sol#L17
[test_whenRoleBearingExternalCallerExecutesTaskDirectly_reverts]: selfExecuteTask.t.sol#L34

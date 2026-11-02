# BurnerLoansSeizerTask.execute coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [execute](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L243). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-EXECUTE` identifies this contract/function.

Execute requires own Kernel activity, authenticates HEART, then returns if disabled. Kernel-inactive execution reverts even when disabled. Own inactivity rejects before any cached ROLES lookup.

HEART role caller; configured gas isolation. Task must be Kernel-active; local enablement is independent. Core/Seize own state checked by actual Lens/action route.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Management requires own Kernel activity, permits local pause, and admits only Core-registered assets. Add/removeAsset remains ADMIN-only; scan/gas limits accept ADMIN or BL admin. Execute checks own Kernel activity before HEART authorization and its disabled no-op. One asset is attempted per invocation using immutable Lens/Seize bindings.

The task reserves 50,000 outer gas for cleanup and forwards at most executionGasLimit to its self-call. Whole-body failure reports at most four return-data bytes and commits asset rotation outside the reverted call. Successful bodies already rotated before scanning. Exactly one asset turn is consumed either way; disabled execution consumes no turn. Per-asset errors emit ScanFailed/SeizureFailed. The bounded Lens honors checked/result limits independently; stale borrower offsets are repaired within the visit, and successful defaults account for borrower-list compaction. Later Heart tasks remain runnable.

## Cursor recovery and comparison with RevenueDistributorTask

ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE can use [setNextAssetIndex](./setNextAssetIndex.md) to choose the next managed asset, and [setNextAssetBorrowerIndex](./setNextAssetBorrowerIndex.md) to select one managed asset's borrower offset. Recovery remains available while locally disabled. Both setters require the Task to be Kernel-active. Zero resets require no downstream reads; a nonzero borrower offset uses a zero-sized Lens scan for bounds validation.

[RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol) advances its asset cursor before each distribution attempt, so a caught per-asset failure moves on. SeizerTask follows that rule for scan and settlement failures. Revenue may attempt several assets within one self-call; SeizerTask attempts one asset per heartbeat. On an entire self-call revert or gas exhaustion, Revenue's in-body cursor writes roll back and its outer execute only reports ExecutionFailed. SeizerTask deliberately advances outside the reverted body, preserving the next asset's turn. Borrower cursors and position accounting remain unchanged on whole-body failure.

| Failure boundary | SeizerTask next asset | RevenueDistributorTask next asset |
| --- | --- | --- |
| Per-asset error caught within a successful task body | Advance before attempt; keep movement | Advance before attempt; keep movement |
| Entire task body reverts or exhausts gas | Outer call advances one asset despite rollback | Cursor movement rolls back with body |

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-A01 | Fuzz outside every HEART holder | Local enabled independently true/false | ROLES_RequireRole(HEART_ROLE) before no-op; no rotation | Covered: [test][test_whenCallerLacksHeartRole_reverts] |
| BLSEIZ-EXECUTE-A02 | Fuzz HEART_ROLE holder | Otherwise ready task | One asset turn admitted | Covered: [test][test_givenHeartRole_whenExecuted_thenAssetRotates] |

## Lifecycle

Fixed for this table: HEART and own Kernel activity are checked. No task-body registry/cursor/Lens/Seize reads.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-L01 | HEART | Task disabled | Return without task call or rotation | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent], [test][test_givenDisabled_whenExecuted_thenNoRotation] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P01 | HEART_ROLE holder | Enabled, no managed assets | Successful no-op | No work; asset iterator zero | Covered: [test][test_givenNoAssets_whenExecuted_thenNoWork] |
| BLSEIZ-EXECUTE-P02 | HEART | Scan/settlement errors caught inside self task | No outer ExecutionFailed if self task returns | Exact inner failure event; rotate; preserve borrower debt on rejected settlement | Covered: [test][test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn], [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |

## Scanning and progress

Fixed for this table: Accounting / events: No selftask partial state; later Heart task still executes.

| ID | Caller | Cursor / gas / registry condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P03 | HEART | Entire self task exhausts its configured budget | ExecutionFailed(0); borrower state rolls back, asset rotation persists | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent], [test][test_givenWholeTaskExhaustsGas_whenExecuted_thenOtherAssetGetsNextHeartbeat] |
| BLSEIZ-EXECUTE-P09 | HEART | Self task reverts with a four-byte custom error | ExecutionFailed(selector); rotate assets | Covered: [test][test_givenSelfCallCustomError_whenExecuted_thenSelectorIsReported] |
| BLSEIZ-EXECUTE-P10 | HEART | Self task reverts with one byte 0xab | ExecutionFailed(0xab000000); zero-pad prefix; rotate assets | Covered: [test][test_givenSelfCallShortError_whenExecuted_thenPrefixIsZeroPadded] |
| BLSEIZ-EXECUTE-P11 | HEART | Self task reverts with 100,000 bytes beginning 0xabcdef01 | ExecutionFailed(0xabcdef01); copy only four bytes; rotate assets | Covered: [test][test_givenSelfCallLargeError_whenExecuted_thenOnlySelectorIsCopied] |
| BLSEIZ-EXECUTE-P12 | HEART | Next asset is the last managed asset; A already has a nonzero borrower cursor; entire B self-call reverts | Outer asset cursor wraps to0; both borrower cursors and principal unchanged | Covered: [test][test_givenLastAsset_whenSelfCallFails_thenRotationWrapsAndBorrowerCursorsStayUnchanged] |
| BLSEIZ-EXECUTE-P07 | HEART | Outer gas below configured body limit | Cap forwarding to retain cleanup; rotate despite bounded failure; no partial debt default | Covered: [test][test_givenOuterGasBelowConfiguredLimit_whenExecuted_thenCleanupAndRotationSurvive] |
| BLSEIZ-EXECUTE-P08 | HEART via task manager | Bounded self-call failure with another task following | Later periodic task executes once; asset rotation persists | Covered: [test][test_givenTaskExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes], [dependency gas exhaustion][test_givenLensExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes] |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-L02 | Fuzz HEART_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Task) before HEART authentication | No task/cursor/dependency calls | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLSEIZ-EXECUTE-L03 | HEART_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Task) | No asset rotation or task body | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |

## Shared assertions

Use existing task manager/later task fixture; prove bounded failing call returns sufficient gas for subsequent task rather than only asserting caught revert.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Test organization

[execute.t.sol](./execute.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.
[execute integration tests](./integration/execute.t.sol) retain the real dependency and accounting interactions.

## Distinct registry progress outcomes

Task enabled; caller holds HEART; Core/Seize ready; sufficient bounded gas. Use fixed managed-asset fixtures so progress and skipped work are observable.

| ID | Caller | Managed assets / authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P04 | HEART_ROLE holder | Exactly one asset; task holds seizer role; healthy scan | Success | One Lens scan, no settlement; asset traversal remains valid; borrower progress follows scan output | Covered: [test][test_givenOneAsset_whenExecuted_thenTraversalRemainsZero] |
| BLSEIZ-EXECUTE-P05 | HEART_ROLE holder | Exactly two assets; task holds seizer role | Success over repeated invocations | A batch 25; B turn; remaining A batch 25; no drain-before-rotation | Covered: [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles], [test][test_givenHeartRole_whenExecuted_thenAssetRotates] |
| BLSEIZ-EXECUTE-P06 | HEART_ROLE holder | Two assets; task lacks seizer role | Successful bounded task with SeizerRoleMissing(asset) | Asset traversal advances; borrower cursor unchanged; no Lens scan; granting role restores scheduling | Covered: [test][test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates] |

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenDisabled_whenExecuted_thenNoRotation]: ./execute.t.sol#L80
[test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles]: ./integration/execute.t.sol#L33
[test_givenHeartRole_whenExecuted_thenAssetRotates]: ./execute.t.sol#L140
[test_givenLastAsset_whenSelfCallFails_thenRotationWrapsAndBorrowerCursorsStayUnchanged]: ./integration/execute.t.sol#L311
[test_givenNoAssets_whenExecuted_thenNoWork]: ./execute.t.sol#L122
[test_givenOuterGasBelowConfiguredLimit_whenExecuted_thenCleanupAndRotationSurvive]: ./integration/execute.t.sol#L254
[test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn]: ./execute.t.sol#L66
[test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates]: ./execute.t.sol#L104
[test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry]: ./integration/execute.t.sol#L203
[test_givenSelfCallCustomError_whenExecuted_thenSelectorIsReported]: ./execute.t.sol#L163
[test_givenSelfCallLargeError_whenExecuted_thenOnlySelectorIsCopied]: ./execute.t.sol#L185
[test_givenSelfCallShortError_whenExecuted_thenPrefixIsZeroPadded]: ./execute.t.sol#L176
[test_givenTaskExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes]: ./integration/execute.t.sol#L273
[test_givenTaskInactive_whenExecuted_reverts]: ./execute.t.sol#L149
[test_givenWholeTaskExhaustsGas_whenExecuted_thenOtherAssetGetsNextHeartbeat]: ./execute.t.sol#L49
[test_whenCallerLacksHeartRole_reverts]: ./execute.t.sol#L94

[test_givenOneAsset_whenExecuted_thenTraversalRemainsZero]: ./execute.t.sol#L270

[test_givenLensExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes]: ./execute.t.sol#L26

[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: execute.t.sol#L293

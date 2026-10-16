# executeQueuedAction scenario plan

Scope: generic RDT execution timing, lifecycle, state-hash checks, callbacks and batch atomicity. Queue plans own action-specific forwarding and live inputs.

Co-located queue getters: after success, getQueuedAction retains proposer/timestamps and reports executed; nextActionId is unchanged; every pendingActionId key is zero and configuration-state count/destination default to zero. getQueuedActionLength/getQueuedSubAction reject the terminal action with its exact ITimelockBatchQueue status error; getQueuedConfigState gives ConfigStateIndexOutOfBounds for cleared slots. On rejection, all metadata, flags, payloads, destinations and key ownership match their pre-call values. Fuzz getter callers, including when RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Permissionless executor: fuzz without exclusions; proposer authority after queue is irrelevant. Delay=1 day, execution window=3 days. Prefix `ITimelockBatchQueue_` applies to timing/flag errors; `IConfigTimelockBatchQueue_` applies to key/hash errors. Standard accessible/time checks occur before RDT enabled/activity/operator checks. Each sub-action checks its hash immediately before dispatch, in array order; earlier writes can stale later hashes. Config locks exclude another unresolved action on the same destination-scoped key. They do not prevent one batch from holding an asset-scoped route key and the separate global yield-recipient key.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Execution success marks executed, clears sub-actions, releases every key and emits ordered per-sub-action logs followed by TimelockActionExecuted. Any failed sub-action rolls back every earlier write/transfer/log, executed flag and key release; queued data remains available for retry or cancellation.

## Lifecycle

| ID | Caller | Action state | RDT Kernel | RDT local | Selected operator | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-E11 | Any executor, fuzz | Ready | Active | Disabled | Yes | Active | Enabled | NotEnabled() | Unchanged | Covered: [configuration][testFuzz_givenTimelockDisabled_whenExecuted_reverts], [rescue][test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts] |
| RDT-E12 | Any executor, fuzz | Ready | Inactive | Enabled | Yes | Active | Enabled | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Unchanged | Covered: [configuration][testFuzz_givenTimelockInactive_whenExecuted_reverts], [rescue][test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts] |
| EXEC-L04 | Any executor, fuzz | Ready | Active | Enabled | No | Active | Enabled | ConfigOperator_Unauthorized(RDT) | Unchanged | Covered: [executor and configuration classes][testFuzz_givenOperatorRotatedAfterQueue_whenConfigurationExecuted_reverts] |
| EXEC-L02 | Any executor, fuzz | Ready configuration | Active | Enabled | Yes | Active | Disabled | NotEnabled() | Unchanged; re-enable RD to retry | Covered: [route creation, route retirement and yield pointer with retry][testFuzz_givenTargetDisabledAfterQueue_whenConfigurationExecuted_revertsThenRetries] |
| EXEC-L05 | Any executor, fuzz | Ready configuration | Active | Enabled | Yes | Inactive | Enabled | RevenueDistributor_PolicyInactive() | Unchanged; reactivate RD to retry | Covered: [evidence][testFuzz_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries] |
| EXEC-L06 | Any executor, fuzz | Ready configuration | Active | Enabled | Yes | Inactive | Disabled | NotEnabled() before RD activity validation | Unchanged; reactivate and re-enable RD to retry | Covered: [evidence][testFuzz_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries] |

## Callbacks

| ID | Caller | Outer dispatch | Nested action relationship | Nested RD write | Callback handling | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-C01 | Token callback executor | Rescue | Fuzz same/independent action | Attempted | Fuzz caught/propagated | Same action sees ActionAlreadyExecuted; independent configuration reaches the RD guard and gives ReentrancyGuardReentrantCall | Caught failure permits one outer payment; propagated failure restores custody, action and key | Covered: [same/independent callback and caught/propagated outcomes][testFuzz_whenRescueTokenCallbacksIntoExecution_preservesAtomicity] |

## Execution window

| ID | Caller | Action validity | Timestamp | RDT/RD state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-E13 | Any executor, fuzz | Valid live action | Fuzz `executableAt..expiresAt` inclusive; seed both bounds | Active/enabled and selected | Success | Queue completed and keys released | Covered: [evidence][testFuzz_whenExecutionIsWithinWindow_anyCallerExecutes] |
| EXEC-I02 | Any executor, fuzz | Valid queued action | Fuzz `queuedAt..executableAt-1` inclusive; seed both bounds | Independently fuzz lifecycle faults | ITimelockBatchQueue_ActionNotReady(id, executableAt) | Unchanged | Covered: [evidence][testFuzz_whenExecutionIsBeforeReady_revertsAndRetainsAction] |
| EXEC-I06 | Any executor, fuzz | Valid queued action | expiry+1..MAX | Independently fuzz lifecycle faults | ITimelockBatchQueue_ActionExpired(id, expiry) | Unchanged; expired owner still holds key | Covered: [evidence][testFuzz_whenExecutionIsExpired_revertsAndRetainsAction] |

## Action status

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXEC-I01 | Any executor, fuzz | Unknown ID, including 0 and uint64.max | ITimelockBatchQueue_ActionNotFound(id) | Unchanged; existence check precedes timing and lifecycle gates | Covered: [evidence][testFuzz_whenActionDoesNotExist_revertsBeforeLifecycleChecks] |
| EXEC-I07 | Any executor, fuzz | Action was cancelled | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; terminal flag check precedes timing and lifecycle gates | Covered: [evidence][testFuzz_whenActionWasCancelled_revertsBeforeLifecycleChecks] |
| EXEC-I08 | Any executor, fuzz | Action already executed | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; terminal flag check precedes timing and lifecycle gates | Covered: [evidence][testFuzz_whenActionAlreadyExecuted_revertsBeforeLifecycleChecks] |
| EXEC-V01 | Any getter caller, fuzz | After successful action and for unknown ID=0/MAX64 | getQueuedAction exposes terminal flags for existing ID; unknown ID gives ITimelockBatchQueue_ActionNotFound(id); length/sub-action give exact terminal or missing-action error | Unknown config-state count/destination and pendingActionId defaults are zero; reads never mutate state | Covered: [evidence][testFuzz_whenExecutedOrUnknownActionRead_returnsTerminalStateAndDefaults] |

## State changes

| ID | Caller | Guarded config after queue | Custody after queue | Pending debt after queue | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDT-E05 | Any executor, fuzz | Encoded state changed | Fuzz unchanged/changed | Fuzz unchanged/changed | ConfigStateChanged(actionId, index, key, expected, actual) | Rollback and retain queue | Covered: [rescue listing][test_givenQueuedActiveAsset_whenRetired_reverts], [route hash][testFuzz_whenRouteChanges_executionRevertsAndRetainsKey], [global hash][testFuzz_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey] |
| EXEC-S02 | Any executor, fuzz | Unchanged | Balance changed, or unchanged | Pending debt changed, or unchanged; at least one changes | Guard hash remains valid; execution proceeds to live input validation | Apply action or its live target error; queue semantics follow that result | Covered: [entitlement increases][test_givenQueuedRequest_whenEntitlementIncreases], [decreases but stays sufficient][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient], [equals request][test_givenQueuedRequest_whenEntitlementEqualsAmount], [custody increases][test_givenQueuedRequest_whenCustodyIncreases] |

## Batch ordering

| ID | Caller | Sub-actions | Asset/key relationship | Execution order | Live recipient/route relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-P02 | Any executor, fuzz | Two route updates | Independent assets/keys | Supplied order | Both compatible | Execute both in order | Both configurations installed atomically | Covered: [executor, ordered sub-action logs and key release][testFuzz_givenTwoDifferentAssetRoutes_whenBatchExecutes] |
| EXEC-I03 | Any executor, fuzz | Route update plus yield-pointer update; batch valid against pre-batch state | Different locks: asset-scoped route key plus global yield key | Fuzz route-first/yield-first | The first sub-action makes the candidate collide with the second: route-first adds it as a route recipient; yield-first changes the value included in `assetDistributionHash` | Route-first: DuplicateRecipient(candidate); yield-first: ConfigStateChanged at later route | Rollback earlier sub-action and all logs; retain both locks and queued sub-actions | Covered: [route first][testFuzz_givenConflictingRouteAndYield_whenRouteFirstBatchExecutes_revertsAtomically], [yield first][testFuzz_givenConflictingRouteAndYield_whenYieldFirstBatchExecutes_revertsAtomically] |
| EXEC-I05 | Any executor, fuzz | Yield-pointer update and route update | Independent asset key plus global key | Fuzz yield-first/route-first | Otherwise compatible | Yield-first: later route ConfigStateChanged because its hash includes global yieldRecipient; compatible route-first then yield succeeds | Yield-first failure rolls back both actions and retains all keys; route-first completes in order | Covered: [both supplied orders and arbitrary executor][testFuzz_givenCompatibleRouteAndYield_whenBatchExecutesInSuppliedOrder] |

## Batch rollback

| ID | Caller | Earlier sub-action | Later sub-action | Post-queue debt state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-I04 | Any executor, fuzz | Surplus transfer | Pending-payout rescue | Requested bucket paid externally before execution | RevenueDistributor_InsufficientPendingDistribution(asset,requested,available) | Earlier transfer rolls back; external payout before this transaction stays settled | Covered: [executor, atomic rollback and queue metadata retention][testFuzz_givenQueuedRescueBatch_whenLaterBucketPaidBeforeExecution_reverts] |

[testFuzz_givenOperatorRotatedAfterQueue_whenConfigurationExecuted_reverts]: ./executeQueuedAction.t.sol
[testFuzz_givenTargetDisabledAfterQueue_whenConfigurationExecuted_revertsThenRetries]: ./executeQueuedAction.t.sol
[testFuzz_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries]: ./executeQueuedAction.t.sol
[test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L776
[test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L785
[test_givenQueuedActiveAsset_whenRetired_reverts]: ./queueRescuePendingPayout.t.sol#L574
[testFuzz_givenTwoDifferentAssetRoutes_whenBatchExecutes]: ./queueBatch.t.sol
[testFuzz_givenConflictingRouteAndYield_whenRouteFirstBatchExecutes_revertsAtomically]: ./queueBatch.t.sol
[testFuzz_givenConflictingRouteAndYield_whenYieldFirstBatchExecutes_revertsAtomically]: ./queueBatch.t.sol
[testFuzz_givenQueuedRescueBatch_whenLaterBucketPaidBeforeExecution_reverts]: ./queueBatch.t.sol
[testFuzz_givenTimelockDisabled_whenExecuted_reverts]: ./executeQueuedAction.t.sol
[testFuzz_givenTimelockInactive_whenExecuted_reverts]: ./executeQueuedAction.t.sol
[testFuzz_whenExecutionIsWithinWindow_anyCallerExecutes]: ./executeQueuedAction.t.sol
[testFuzz_whenExecutionIsBeforeReady_revertsAndRetainsAction]: ./executeQueuedAction.t.sol
[testFuzz_whenExecutionIsExpired_revertsAndRetainsAction]: ./executeQueuedAction.t.sol
[testFuzz_whenActionDoesNotExist_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol
[testFuzz_whenActionWasCancelled_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol
[testFuzz_whenActionAlreadyExecuted_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol
[testFuzz_whenExecutedOrUnknownActionRead_returnsTerminalStateAndDefaults]: ./executeQueuedAction.t.sol
[testFuzz_whenRouteChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L417
[testFuzz_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenRescueTokenCallbacksIntoExecution_preservesAtomicity]: ./queueBatch.t.sol
[testFuzz_givenCompatibleRouteAndYield_whenBatchExecutesInSuppliedOrder]: ./queueBatch.t.sol
[test_givenQueuedRequest_whenEntitlementIncreases]: ./queueRescuePendingPayout.t.sol#L424
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient]: ./queueRescuePendingPayout.t.sol#L446
[test_givenQueuedRequest_whenEntitlementEqualsAmount]: ./queueRescuePendingPayout.t.sol#L468
[test_givenQueuedRequest_whenCustodyIncreases]: ./queueRescuePendingPayout.t.sol#L490

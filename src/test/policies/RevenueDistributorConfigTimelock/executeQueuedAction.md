# executeQueuedAction scenario plan

Shared action existence, terminal-status and execution-window checks precede concrete admission. Execution then requires own Kernel activity before local enablement and target checks; its caller remains permissionless.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: generic RDT execution timing, lifecycle, state-hash checks, callbacks and batch atomicity. Queue plans own action-specific forwarding and live inputs.

Co-located queue getters: after success, getQueuedAction retains proposer/timestamps and reports executed; nextActionId is unchanged; every pendingActionId key is zero and configuration-state count/destination default to zero. getQueuedActionLength/getQueuedSubAction reject the terminal action with its exact ITimelockBatchQueue status error; getQueuedConfigState gives ConfigStateIndexOutOfBounds for cleared slots. On rejection, all metadata, flags, payloads, destinations and key ownership match their pre-call values. Fuzz getter callers, including when RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Permissionless executor: fuzz without exclusions; proposer authority after queue is irrelevant. Delay=1 day, execution window=3 days. Prefix `ITimelockBatchQueue_` applies to timing/flag errors; `IConfigTimelockBatchQueue_` applies to key/hash errors. Standard accessible/time checks occur before RDT enabled/activity/operator checks. Each sub-action checks its hash immediately before dispatch, in array order; earlier writes can stale later hashes. Config locks exclude another unresolved action on the same destination-scoped key. They do not prevent one batch from holding an asset-scoped route key and the separate global yield-recipient key.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Execution success marks executed, clears sub-actions, releases every key and emits ordered per-sub-action logs followed by TimelockActionExecuted. Any failed sub-action rolls back every earlier write/transfer/log, executed flag and key release; queued data remains available for retry or cancellation.

## Lifecycle

| ID | Caller | Local active | Local enabled | Action state | Selected operator | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-EXECUTE-E11 | Any executor, fuzz | true | false | Ready | Yes | true | true | NotEnabled() | Unchanged | Covered: [configuration][test_givenTimelockDisabled_whenExecuted_reverts], [rescue][test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts] |
| RDCT-EXECUTE-E12 | Any executor, fuzz | false | true | Ready | Yes | true | true | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Unchanged | Covered: [configuration][test_givenTimelockInactive_whenExecuted_reverts], [rescue][test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts] |
| EXEC-L04 | Any executor, fuzz | true | true | Ready | No | true | true | ConfigOperator_Unauthorized(RDT) | Unchanged | Covered: [executor and configuration classes][test_givenOperatorRotatedAfterQueue_whenConfigurationExecuted_reverts] |
| EXEC-L02 | Any executor, fuzz | true | true | Ready configuration | Yes | true | false | NotEnabled() | Unchanged; re-enable RD to retry | Covered: [route creation, route retirement and yield pointer with retry][test_givenTargetDisabledAfterQueue_whenConfigurationExecuted_revertsThenRetries] |
| EXEC-L05 | Any executor, fuzz | true | true | Ready configuration | Yes | false | true | RevenueDistributor_PolicyNotActive(RD) | Unchanged; reactivate RD to retry | Covered: [evidence][test_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries] |
| EXEC-L06 | Any executor, fuzz | true | true | Ready configuration | Yes | false | false | RevenueDistributor_PolicyNotActive(RD) before target local enablement | Unchanged; reactivate and re-enable RD to retry | Covered: [evidence][test_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries] |

## Callbacks

| ID | Caller | Outer dispatch | Nested action relationship | Nested RD write | Callback handling | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-C01 | Token callback executor | Rescue | Same action | Attempted | Caught | Nested ActionAlreadyExecuted; outer success | Pay once, complete outer action and release key | Covered: [test][test_givenSameActionCallback_whenNestedFailureCaught] |
| EXEC-C02 | Token callback executor | Rescue | Independent ready configuration | Attempted | Caught | Nested ReentrancyGuardReentrantCall; outer success | Pay once; independent action/key retained and RD unchanged | Covered: [test][test_givenIndependentActionCallback_whenNestedFailureCaught] |
| EXEC-C03 | Token callback executor | Rescue | Same action | Attempted | Propagated | ReentrantFeeToken.CallbackFailed() | Whole rescue/action/key rollback; no payment | Covered: [test][test_givenSameActionCallback_whenNestedFailurePropagated_reverts] |
| EXEC-C04 | Token callback executor | Rescue | Independent ready configuration | Attempted | Propagated | ReentrantFeeToken.CallbackFailed() | Both actions/keys retained; no payment or RD write | Covered: [test][test_givenIndependentActionCallback_whenNestedFailurePropagated_reverts] |

## Execution window

| ID | Caller | Local active | Local enabled | Action validity | Timestamp | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-EXECUTE-E13 | Any executor, fuzz | true | true | Valid live action | Fuzz `executableAt..expiresAt` inclusive; seed both bounds | true | true | Success | Queue completed and keys released | Covered: [evidence][test_whenExecutionIsWithinWindow_anyCallerExecutes] |
| EXEC-I02 | Any executor, fuzz | true | true | Valid queued action | Fuzz `queuedAt..executableAt-1` inclusive; seed both bounds | true | true | ITimelockBatchQueue_ActionNotReady(id, executableAt) | Unchanged | Covered: [evidence][test_whenExecutionIsBeforeReady_revertsAndRetainsAction] |
| EXEC-I06 | Any executor, fuzz | true | true | Valid queued action | expiry+1..MAX | true | true | ITimelockBatchQueue_ActionExpired(id, expiry) | Unchanged; expired owner still holds key | Covered: [evidence][test_whenExecutionIsExpired_revertsAndRetainsAction] |

## Action status

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXEC-I01 | Any executor, fuzz | Unknown ID, including 0 and uint64.max | ITimelockBatchQueue_ActionNotFound(id) | Unchanged; existence check precedes timing and lifecycle gates | Covered: [evidence][test_whenActionDoesNotExist_revertsBeforeLifecycleChecks] |
| EXEC-I07 | Any executor, fuzz | Action was cancelled | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; terminal flag check precedes timing and lifecycle gates | Covered: [evidence][test_whenActionWasCancelled_revertsBeforeLifecycleChecks] |
| EXEC-I08 | Any executor, fuzz | Action already executed | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; terminal flag check precedes timing and lifecycle gates | Covered: [evidence][test_whenActionAlreadyExecuted_revertsBeforeLifecycleChecks] |
| EXEC-V01 | Any getter caller, fuzz | After successful action and for unknown ID=0/MAX64 | getQueuedAction exposes terminal flags for existing ID; unknown ID gives ITimelockBatchQueue_ActionNotFound(id); length/sub-action give exact terminal or missing-action error | Unknown config-state count/destination and pendingActionId defaults are zero; reads never mutate state | Covered: [evidence][test_whenExecutedOrUnknownActionRead_returnsTerminalStateAndDefaults] |

## State changes

| ID | Caller | Guarded config after queue | Custody after queue | Pending debt after queue | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-EXECUTE-E05 | Any executor, fuzz | Encoded state changed | Fuzz unchanged/changed | Fuzz unchanged/changed | ConfigStateChanged(actionId, index, key, expected, actual) | Rollback and retain queue | Covered: [rescue listing][test_givenQueuedActiveAsset_whenRetired_reverts], [route hash][test_whenRouteChanges_executionRevertsAndRetainsKey], [global hash][test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey] |
| EXEC-S02 | Any executor, fuzz | Unchanged | Balance changed, or unchanged | Pending debt changed, or unchanged; at least one changes | Guard hash remains valid; execution proceeds to live input validation | Apply action or its live target error; queue semantics follow that result | Covered: [entitlement increases][test_givenQueuedRequest_whenEntitlementIncreases], [decreases but stays sufficient][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient], [equals request][test_givenQueuedRequest_whenEntitlementEqualsAmount], [custody increases][test_givenQueuedRequest_whenCustodyIncreases] |

## Batch ordering

| ID | Caller | Sub-actions | Asset/key relationship | Execution order | Live recipient/route relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-P02 | Any executor, fuzz | Two route updates | Independent assets/keys | Supplied order | Both compatible | Execute both in order | Both configurations installed atomically | Covered: [executor, ordered sub-action logs and key release][test_givenTwoDifferentAssetRoutes_whenBatchExecutes] |
| EXEC-I03 | Any executor, fuzz | Route update plus yield-pointer update; batch valid against pre-batch state | Different locks: asset-scoped route key plus global yield key | Fuzz route-first/yield-first | The first sub-action makes the candidate collide with the second: route-first adds it as a route recipient; yield-first changes the value included in `assetDistributionHash` | Route-first: DuplicateRecipient(candidate); yield-first: ConfigStateChanged at later route | Rollback earlier sub-action and all logs; retain both locks and queued sub-actions | Covered: [route first][test_givenConflictingRouteAndYield_whenRouteFirstBatchExecutes_revertsAtomically], [yield first][test_givenConflictingRouteAndYield_whenYieldFirstBatchExecutes_revertsAtomically] |
| EXEC-I05 | Any executor, fuzz | Yield-pointer update and route update | Independent asset key plus global key | Fuzz yield-first/route-first | Otherwise compatible | Yield-first: later route ConfigStateChanged because its hash includes global yieldRecipient; compatible route-first then yield succeeds | Yield-first failure rolls back both actions and retains all keys; route-first completes in order | Covered: [both supplied orders and arbitrary executor][test_givenCompatibleRouteAndYield_whenBatchExecutesInSuppliedOrder] |

## Batch rollback

| ID | Caller | Earlier sub-action | Later sub-action | Post-queue debt state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-I04 | Any executor, fuzz | Surplus transfer | Pending-payout rescue | Requested bucket paid externally before execution | RevenueDistributor_InsufficientPendingDistribution(asset,requested,available) | Earlier transfer rolls back; external payout before this transaction stays settled | Covered: [executor, atomic rollback and queue metadata retention][test_givenQueuedRescueBatch_whenLaterBucketPaidBeforeExecution_reverts] |

## Rescue-specific changes before execution

Execute the stored amount=4 at a valid ready timestamp. Expect one unchanged RD call. Success pays 4, updates entitlement, completes the action and releases its key. Failure preserves the pending action/key and rolls back payment/debt; match exact error data. The rows below also cover concrete RDT execution gates and permissionless callers.

| ID | Caller | Change after queue | Execution outcome / effects | Test |
| --- | --- | --- | --- | --- |
| RDT-E03 | Fuzz executor | Entitlement increases from 10 to 12; stored amount=4 | Hash unchanged; pay exactly 4, leave entitlement=8; complete action and release key | Covered: [test][test_givenQueuedRequest_whenEntitlementIncreases] |
| RDT-E04 | Fuzz executor | Entitlement decreases to 3; stored amount=4 | RevenueDistributor_InsufficientPendingDistribution(asset,4,3); no transfer; retain action/key | Covered: [test][test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts] |
| RDT-E06 | Fuzz executor | Token rejects the stored recovery transfer | Exact configured token failure; balances/entitlement and whole action/key state roll back | Covered: [test][test_givenQueuedRequest_whenTokenRejectsTransfer_reverts] |
| RDT-E09 | Fuzz executor | Routes change while asset stays Active and original recipient remains entitled to at least 4 | Hash unchanged; pay stored 4 using current entitlement; no duplicated RD allocation calculation | Covered: [test][test_givenQueuedFixedRecipient_whenRouteChanges] |
| RDT-E10 | Executor | RD becomes Kernel-inactive after a valid queue | `RevenueDistributor_PolicyNotActive(RD)`; action/key retained, no payment | Covered: [distributor becomes inactive][test_givenQueuedRequest_whenDistributorBecomesInactive_reverts] |
| RDT-E11 | Fuzz executor | Entitlement decreases from 10 to 6 | Pay stored 4; leave entitlement=2 | Covered: [test][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient], [test][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_AdminOnlySeed], [test][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_RevenueRoleOnlySeed], [test][test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_RolesOverlapSeed] |
| RDT-E12 | Fuzz executor | Entitlement equals stored amount=4 | Pay 4; leave entitlement=0 | Covered: [test][test_givenQueuedRequest_whenEntitlementEqualsAmount], [test][test_givenQueuedRequest_whenEntitlementEqualsAmount_AdminOnlySeed], [test][test_givenQueuedRequest_whenEntitlementEqualsAmount_RevenueRoleOnlySeed], [test][test_givenQueuedRequest_whenEntitlementEqualsAmount_RolesOverlapSeed] |
| RDT-E13 | Fuzz executor | Custody grows; original recipient entitlement remains 10 | Pay 4; leave entitlement=6; no stale-hash rejection | Covered: [test][test_givenQueuedRequest_whenCustodyIncreases], [test][test_givenQueuedRequest_whenCustodyIncreases_AdminOnlySeed], [test][test_givenQueuedRequest_whenCustodyIncreases_RevenueRoleOnlySeed], [test][test_givenQueuedRequest_whenCustodyIncreases_RolesOverlapSeed] |
| RDT-E14 | Fuzz executor | Original entitlement becomes zero | RevenueDistributor_InsufficientPendingDistribution(asset,4,0); action/key retained | Covered: [test][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts], [test][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_AdminOnlySeed], [test][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_RevenueRoleOnlySeed], [test][test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_RolesOverlapSeed] |
| RDT-E15 | Fuzz executor | Repurchase recipient changes and original entitlement disappears | Exact live insufficient-entitlement error; action/key retained | Covered: [test][test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts], [test][test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_AdminOnlySeed], [test][test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_RevenueRoleOnlySeed], [test][test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_RolesOverlapSeed] |
| RDT-E16 | Fuzz executor | Treasury module changes and original role-recipient entitlement disappears | Exact live insufficient-entitlement error; action/key retained | Covered: [test][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts], [test][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_AdminOnlySeed], [test][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_RevenueRoleOnlySeed], [test][test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_RolesOverlapSeed] |
| RDT-E17 | Fuzz executor | Custody drops below required transfer | Exact RD custody/delivery error; no partial entitlement or action/key change | Covered: [test][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts], [test][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_AdminOnlySeed], [test][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_RevenueRoleOnlySeed], [test][test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_RolesOverlapSeed] |
| RDT-E18 | Fuzz executor | Yield recipient changes; original fixed recipient remains entitled | Pay stored 4; no hash invalidation from unrelated recipient selection | Covered: [test][test_givenQueuedFixedRecipient_whenYieldRecipientChanges], [test][test_givenQueuedFixedRecipient_whenYieldRecipientChanges_AdminOnlySeed], [test][test_givenQueuedFixedRecipient_whenYieldRecipientChanges_RevenueRoleOnlySeed], [test][test_givenQueuedFixedRecipient_whenYieldRecipientChanges_RolesOverlapSeed] |
| RDT-E19 | Fuzz executor | Treasury changes; original fixed recipient remains entitled | Pay stored 4; no hash invalidation from unrelated Treasury selection | Covered: [test][test_givenQueuedFixedRecipient_whenTreasuryUpgraded], [test][test_givenQueuedFixedRecipient_whenTreasuryUpgraded_AdminOnlySeed], [test][test_givenQueuedFixedRecipient_whenTreasuryUpgraded_RevenueRoleOnlySeed], [test][test_givenQueuedFixedRecipient_whenTreasuryUpgraded_RolesOverlapSeed] |

[test_givenOperatorRotatedAfterQueue_whenConfigurationExecuted_reverts]: ./executeQueuedAction.t.sol#L374
[test_givenTargetDisabledAfterQueue_whenConfigurationExecuted_revertsThenRetries]: ./executeQueuedAction.t.sol#L247
[test_givenTargetInactiveAfterQueue_whenExecuted_revertsThenRetries]: ./executeQueuedAction.t.sol#L279
[test_givenQueuedRequest_givenTimelockDisabled_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L860
[test_givenQueuedRequest_givenTimelockInactive_whenExecuted_reverts]: ./queueRescuePendingPayout.t.sol#L869
[test_givenQueuedActiveAsset_whenRetired_reverts]: ./queueRescuePendingPayout.t.sol#L632
[test_givenTwoDifferentAssetRoutes_whenBatchExecutes]: ./queueBatch.t.sol#L1340
[test_givenConflictingRouteAndYield_whenRouteFirstBatchExecutes_revertsAtomically]: ./queueBatch.t.sol#L1087
[test_givenConflictingRouteAndYield_whenYieldFirstBatchExecutes_revertsAtomically]: ./queueBatch.t.sol#L1123
[test_givenQueuedRescueBatch_whenLaterBucketPaidBeforeExecution_reverts]: ./queueBatch.t.sol#L74
[test_givenTimelockDisabled_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L314
[test_givenTimelockInactive_whenExecuted_reverts]: ./executeQueuedAction.t.sol#L329
[test_whenExecutionIsWithinWindow_anyCallerExecutes]: ./executeQueuedAction.t.sol#L26
[test_whenExecutionIsBeforeReady_revertsAndRetainsAction]: ./executeQueuedAction.t.sol#L63
[test_whenExecutionIsExpired_revertsAndRetainsAction]: ./executeQueuedAction.t.sol#L94
[test_whenActionDoesNotExist_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol#L125
[test_whenActionWasCancelled_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol#L142
[test_whenActionAlreadyExecuted_revertsBeforeLifecycleChecks]: ./executeQueuedAction.t.sol#L159
[test_whenExecutedOrUnknownActionRead_returnsTerminalStateAndDefaults]: ./executeQueuedAction.t.sol#L176
[test_whenRouteChanges_executionRevertsAndRetainsKey]: ./queueSetAssetRoutes.t.sol#L431
[test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueSetYieldRecipient.t.sol#L419
[test_givenCompatibleRouteAndYield_whenBatchExecutesInSuppliedOrder]: ./queueBatch.t.sol#L1167
[test_givenQueuedRequest_whenEntitlementIncreases]: ./queueRescuePendingPayout.t.sol#L458
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient]: ./queueRescuePendingPayout.t.sol#L480
[test_givenQueuedRequest_whenEntitlementEqualsAmount]: ./queueRescuePendingPayout.t.sol#L508
[test_givenQueuedRequest_whenCustodyIncreases]: ./queueRescuePendingPayout.t.sol#L536
[test_givenQueuedFixedRecipient_whenTreasuryUpgraded]: ./queueRescuePendingPayout.t.sol#L702
[test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts]: ./queueRescuePendingPayout.t.sol#L727
[test_givenQueuedRequest_whenDistributorBecomesInactive_reverts]: ./queueRescuePendingPayout.t.sol#L842
[test_givenQueuedFixedRecipient_whenRouteChanges]: ./queueRescuePendingPayout.t.sol#L660
[test_givenQueuedRequest_whenEntitlementIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L561
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts]: ./queueRescuePendingPayout.t.sol#L765
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts]: ./queueRescuePendingPayout.t.sol#L817
[test_givenQueuedRequest_whenTokenRejectsTransfer_reverts]: ./queueRescuePendingPayout.t.sol#L800
[test_givenQueuedFixedRecipient_whenYieldRecipientChanges]: ./queueRescuePendingPayout.t.sol#L677
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts]: ./queueRescuePendingPayout.t.sol#L593
[test_givenSameActionCallback_whenNestedFailureCaught]: ./executeQueuedActionCallback.t.sol#L13
[test_givenIndependentActionCallback_whenNestedFailureCaught]: ./executeQueuedActionCallback.t.sol#L26
[test_givenSameActionCallback_whenNestedFailurePropagated_reverts]: ./executeQueuedActionCallback.t.sol#L40
[test_givenIndependentActionCallback_whenNestedFailurePropagated_reverts]: ./executeQueuedActionCallback.t.sol#L51
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1406
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1418
[test_givenQueuedRequest_whenEntitlementDecreasesButRemainsSufficient_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1430
[test_givenQueuedRequest_whenEntitlementEqualsAmount_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1442
[test_givenQueuedRequest_whenEntitlementEqualsAmount_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1452
[test_givenQueuedRequest_whenEntitlementEqualsAmount_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1462
[test_givenQueuedRequest_whenCustodyIncreases_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1327
[test_givenQueuedRequest_whenCustodyIncreases_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1332
[test_givenQueuedRequest_whenCustodyIncreases_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1337
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1374
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1384
[test_givenQueuedRequest_whenEntitlementAlreadyPaid_reverts_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1396
[test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1291
[test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1303
[test_givenQueuedRepurchaseRecipient_whenRepurchaseRecipientChanges_reverts_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1315
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1472
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1482
[test_givenQueuedTreasuryRecipient_whenTreasuryUpgraded_reverts_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1494
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1342
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1352
[test_givenQueuedRequest_whenCustodyIsInsufficient_reverts_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1364
[test_givenQueuedFixedRecipient_whenYieldRecipientChanges_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1261
[test_givenQueuedFixedRecipient_whenYieldRecipientChanges_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1271
[test_givenQueuedFixedRecipient_whenYieldRecipientChanges_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1281
[test_givenQueuedFixedRecipient_whenTreasuryUpgraded_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1231
[test_givenQueuedFixedRecipient_whenTreasuryUpgraded_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1241
[test_givenQueuedFixedRecipient_whenTreasuryUpgraded_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1251

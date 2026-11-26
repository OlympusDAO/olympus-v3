# queueBatch scenario plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: RDT batching, selector/payload validation and conflict-key acquisition. Selector-specific downstream behavior belongs to each queue plan; execution order and atomicity belong to [executeQueuedAction](./executeQueuedAction.md).

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT Kernel-active, RDT enabled, permitted proposer, selected as RD configOperator, RD Kernel-active and locally enabled. Error order follows that list: own RevenueDistributorConfigTimelock_PolicyNotActive(RDT), NotEnabled(), NotAuthorised(), then selected-operator and target checks. Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Batch bounds 1..15 inclusive; each supported action has one key. Route/retirement/surplus-rescue/pending-rescue for the same asset share one key. Global yield-recipient replacement is outside this queue's delegated authority and must reject as an unsupported selector. Surplus requires NeverListed, while pending debt requires an asset that has been managed, so both rescue previews cannot simultaneously be valid for one asset. Across separate queued actions, an Admin can list/fund a formerly NeverListed asset while its old surplus action owns the key; a newly valid pending request then fails with ConfigKeyPending. Rescue selectors have their own preview/lifecycle rules documented in their plans.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Local active | Local enabled | Operator binding | Distributor active | Distributor enabled | Batch | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-A01 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | true | true | Selected | true | true | Nonempty supported action | NotAuthorised() | Queue unchanged | Covered: [excluded authorized roles][test_givenUnauthorizedCaller_whenBatchQueued_reverts], [known identities][test_whenKnownUnauthorizedIdentitiesQueueBatch_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Selected operator | Distributor active | Distributor enabled | Batch | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-L01 | Fuzz permitted role caller | true | false | Yes | true | true | Valid nonempty | NotEnabled() | Queue unchanged | Covered: [test][test_givenDisabled_whenBatchQueued_reverts], [test][test_givenDisabled_whenBatchQueued_reverts_AdminOnlySeed], [test][test_givenDisabled_whenBatchQueued_reverts_RevenueRoleOnlySeed], [test][test_givenDisabled_whenBatchQueued_reverts_RolesOverlapSeed] |
| BATCH-L02 | Fuzz permitted role caller | false | true | Yes | true | true | Valid nonempty | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Queue unchanged | Covered: [test][test_givenPolicyInactive_whenBatchQueued_reverts], [test][test_givenPolicyInactive_whenBatchQueued_reverts_AdminOnlySeed], [test][test_givenPolicyInactive_whenBatchQueued_reverts_RevenueRoleOnlySeed], [test][test_givenPolicyInactive_whenBatchQueued_reverts_RolesOverlapSeed] |
| BATCH-L03 | Fuzz permitted role caller | true | true | No | true | true | Valid nonempty | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [test][test_givenOperatorRotated_whenBatchQueued_reverts], [test][test_givenOperatorRotated_whenBatchQueued_reverts_AdminOnlySeed], [test][test_givenOperatorRotated_whenBatchQueued_reverts_RevenueRoleOnlySeed], [test][test_givenOperatorRotated_whenBatchQueued_reverts_RolesOverlapSeed] |

## Downstream lifecycle

| ID | Caller | Distributor active | Distributor enabled | First action | Later action | Asset-key relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-P02 | Fuzz permitted role caller | true | false | Valid rescue | Valid rescue | Independent assets | Rescue-only batch queues | No payment at queue | Covered: [test][test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch], [test][test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_AdminOnlySeed], [test][test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_RevenueRoleOnlySeed], [test][test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_RolesOverlapSeed] |
| BATCH-I07 | Fuzz permitted role caller | true | false | Valid rescue | Route update | Independent valid keys | PolicyDependency_NotActive(RD) | Entire batch and prior key acquisition roll back | Covered: [test][test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically], [test][test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_AdminOnlySeed], [test][test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_RevenueRoleOnlySeed], [test][test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_RolesOverlapSeed] |
| BATCH-I08 | Fuzz permitted role caller | true | false | Valid rescue | Route retirement | Independent valid keys | PolicyDependency_NotActive(RD) | Entire batch and prior key acquisition roll back | Covered: [test][test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically], [test][test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_AdminOnlySeed], [test][test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_RevenueRoleOnlySeed], [test][test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_RolesOverlapSeed] |

## Batch size

| ID | Caller | Batch length | Action validity | Key relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-P01 | Fuzz permitted role caller | Fuzz 1..15; seed 1,2,15 | All valid | Independent | Success | Exact ordered sub-actions, all keys/hashes; next ID increments once | Covered: [test][test_whenValidSizedBatchQueued_storesEveryActionAndGuard], [test][test_whenValidSizedBatchQueued_storesEveryActionAndGuard_AdminOnlySeed], [test][test_whenValidSizedBatchQueued_storesEveryActionAndGuard_RevenueRoleOnlySeed], [test][test_whenValidSizedBatchQueued_storesEveryActionAndGuard_RolesOverlapSeed], [test][test_whenMaximumBatchQueued], [test][test_whenMaximumBatchQueued_AdminOnlySeed], [test][test_whenMaximumBatchQueued_RevenueRoleOnlySeed], [test][test_whenMaximumBatchQueued_RolesOverlapSeed] |

## Invalid batch size

| ID | Caller | Batch length | Action validity | Common lifecycle | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-I01 | Fuzz permitted role caller | 0 | N/A | Locally active and enabled | ITimelockBatchQueue_BatchEmpty() after local activity, enablement and proposer admission | Queue unchanged | Covered: [test][test_whenEmptyBatchQueued_reverts] |
| BATCH-I10 | Fuzz permitted role caller | 16 | Otherwise valid | Locally active and enabled | ITimelockBatchQueue_BatchTooLarge(16, 15) after local activity, enablement and proposer admission | Queue unchanged | Covered: [test][test_whenBatchExceedsMaximum_reverts] |

## Target and selector inputs

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| BATCH-I02 | Fuzz permitted role caller | Unsupported target at first position | RevenueDistributorConfigTimelock_InvalidAction(target, selector) | Queue and next ID unchanged | Covered: [test][test_whenFirstActionTargetOrSelectorUnsupported_reverts], [test][test_whenFirstActionTargetOrSelectorUnsupported_reverts_AdminOnlySeed], [test][test_whenFirstActionTargetOrSelectorUnsupported_reverts_RevenueRoleOnlySeed], [test][test_whenFirstActionTargetOrSelectorUnsupported_reverts_RolesOverlapSeed] |
| BATCH-I11 | Fuzz permitted role caller; seed exclusive roles and overlap | Unsupported selector at first position: arbitrary invalid selector or setYieldRecipient with a valid candidate payload | RevenueDistributorConfigTimelock_InvalidAction(target,selector) | No ID, keys or pointer changes | Covered: [first action][test_whenFirstActionTargetOrSelectorUnsupported_reverts], [ADMIN][test_whenFirstActionTargetOrSelectorUnsupported_reverts_AdminOnlySeed], [proposer][test_whenFirstActionTargetOrSelectorUnsupported_reverts_RevenueRoleOnlySeed], [overlap][test_whenFirstActionTargetOrSelectorUnsupported_reverts_RolesOverlapSeed] |
| BATCH-I12 | Fuzz permitted role caller; seed exclusive roles and overlap | Unsupported arbitrary selector or setYieldRecipient after a valid asset route | RevenueDistributorConfigTimelock_InvalidAction(target,selector) | Rollback prior key acquisition and ID; route can queue again; pointer unchanged | Covered: [later action][test_whenLaterActionUnsupported_rollsBackEarlierKey], [ADMIN][test_whenLaterActionUnsupported_rollsBackEarlierKey_AdminOnlySeed], [proposer][test_whenLaterActionUnsupported_rollsBackEarlierKey_RevenueRoleOnlySeed], [overlap][test_whenLaterActionUnsupported_rollsBackEarlierKey_RolesOverlapSeed] |

## Payload inputs

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| BATCH-I03 | Fuzz permitted role caller | Static disable length not 32; surplus length not 64; pending-rescue length not 128; truncated/trailing word | RevenueDistributorConfigTimelock_InvalidAction(target,selector) | Queue unchanged | Covered: [test][test_whenStaticPayloadLengthIsInvalid_reverts], [test][test_whenStaticPayloadLengthIsInvalid_reverts_AdminOnlySeed], [test][test_whenStaticPayloadLengthIsInvalid_reverts_RevenueRoleOnlySeed], [test][test_whenStaticPayloadLengthIsInvalid_reverts_RolesOverlapSeed] |
| QBATCH-V01 | Fuzz all getter callers; queue setup by ADMIN_ROLE holder | Successfully queued live batch; sub-action index=length or MAX | ITimelockBatchQueue_SubActionIndexOutOfBounds(id,index,length) | Read only; valid 0..length-1 indexes return exact supplied actions | Covered: [evidence][test_whenLiveBatchRead_returnsExactSubActionsAndRejectsInvalidIndex] |
| QBATCH-V02 | Fuzz all getter callers; queue setup by ADMIN_ROLE holder | Live batch, unknown ID, or cleared configuration slot; key index=count or MAX | IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(id,subIndex,keyIndex,count) | Read only; valid indexes expose independently expected keys/hashes | Covered: [evidence][test_whenQueuedConfigRead_returnsExactStateAndDefaults] |
| BATCH-I04 | Fuzz permitted role caller | setAssetRoutes missing its dynamic offset, or decodable but noncanonical shifted offsets/trailing bytes | Raw ABI decode failure for the missing offset; decodable noncanonical gives InvalidAction(target,selector) | Queue unchanged | Covered: [test][test_whenRoutePayloadEncodingIsInvalid_reverts], [test][test_whenRoutePayloadEncodingIsInvalid_reverts_AdminOnlySeed], [test][test_whenRoutePayloadEncodingIsInvalid_reverts_RevenueRoleOnlySeed], [test][test_whenRoutePayloadEncodingIsInvalid_reverts_RolesOverlapSeed] |
| BATCH-I05 | Fuzz permitted role caller | Dirty upper bits in the first address word of route, retirement, surplus-rescue or pending-rescue payload | Solidity ABI decode failure at queue time | Queue unchanged; no target effect or queue ownership | Covered: [test][test_whenAddressWordHasDirtyUpperBits_revertsAtQueue], [test][test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_AdminOnlySeed], [test][test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_RevenueRoleOnlySeed], [test][test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_RolesOverlapSeed] |

## Key conflicts

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-BATCH-Q02 | Fuzz permitted role caller | Same key already queued, or twice in batch; route/retire/pending-rescue pairs on a managed asset with valid previews; surplus/surplus on a NeverListed asset. Exclude same-batch surplus/pending pair | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | Atomic queue rollback | Covered: [test][test_whenReachableAssetActionsShareKey_batchReverts], [test][test_whenReachableAssetActionsShareKey_batchReverts_AdminOnlySeed], [test][test_whenReachableAssetActionsShareKey_batchReverts_RevenueRoleOnlySeed], [test][test_whenReachableAssetActionsShareKey_batchReverts_RolesOverlapSeed], [test][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts], [test][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_AdminOnlySeed], [test][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_RevenueRoleOnlySeed], [test][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_RolesOverlapSeed] |
| BATCH-Q02 | Fuzz permitted role caller | Actions use distinct asset keys | Success | Independent keys queue with no RD changes; proposer-only route batch executes after delay without recipient/custody changes | Covered: [test][test_givenQueuedRoute_whenOtherAssetRouteQueued], [test][test_givenQueuedRoute_whenOtherAssetRouteQueued_AdminOnlySeed], [test][test_givenQueuedRoute_whenOtherAssetRouteQueued_RevenueRoleOnlySeed], [test][test_givenQueuedRoute_whenOtherAssetRouteQueued_RolesOverlapSeed], [execution][test_givenTwoDifferentAssetRoutes_whenBatchExecutes] |

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-L04 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; empty batch where exposed | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | No ID, guard, payload or committed log | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts] |
| BATCH-L05 | Fuzz all callers | true | false | ROLES code rejects; empty batch where exposed | NotEnabled() | No ID, guard, payload or committed log | Covered: [test][test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts] |
| BATCH-A02 | Fuzz outside both accepted proposer roles | true | true | Target inactive or required metadata rejects; empty batch where exposed | NotAuthorised() | No ID, guard, payload or committed log | Covered: [test][test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts] |
| BATCH-L06 | Fuzz permitted proposer roles; seed exclusive roles and overlap | true | false | Empty batch | NotEnabled() | No ID, payload, guard or log | Covered: [fuzz][test_givenDisabled_whenEmptyBatchQueued_reverts], [seed][test_whenEmptyBatchQueued_reverts_AdminOnlySeed], [seed][test_whenEmptyBatchQueued_reverts_RevenueRoleOnlySeed], [seed][test_whenEmptyBatchQueued_reverts_RolesOverlapSeed] |
| BATCH-L07 | Fuzz permitted proposer roles; seed exclusive roles and overlap | false | true | Empty batch | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | No ID, payload, guard or log | Covered: [fuzz][test_givenInactive_whenEmptyBatchQueued_reverts] |
| BATCH-L08 | Fuzz permitted proposer roles; seed exclusive roles and overlap | true | false | 16-action batch | NotEnabled() | No ID, payload, guard or log | Covered: [fuzz][test_givenDisabled_whenBatchExceedsMaximum_reverts], [seed][test_whenBatchExceedsMaximum_reverts_AdminOnlySeed], [seed][test_whenBatchExceedsMaximum_reverts_RevenueRoleOnlySeed], [seed][test_whenBatchExceedsMaximum_reverts_RolesOverlapSeed] |
| BATCH-L09 | Fuzz permitted proposer roles; seed exclusive roles and overlap | false | true | 16-action batch | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | No ID, payload, guard or log | Covered: [fuzz][test_givenInactive_whenBatchExceedsMaximum_reverts] |

[test_givenOperatorRotated_whenBatchQueued_reverts]: ./queueBatch.t.sol#L190
[test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically]: ./queueBatch.t.sol#L215
[test_whenFirstActionTargetOrSelectorUnsupported_reverts]: ./queueBatch.t.sol#L364
[test_whenLaterActionUnsupported_rollsBackEarlierKey]: ./queueBatch.t.sol#L397
[test_whenStaticPayloadLengthIsInvalid_reverts]: ./queueBatch.t.sol#L437
[test_whenRoutePayloadEncodingIsInvalid_reverts]: ./queueBatch.t.sol#L493
[test_whenAddressWordHasDirtyUpperBits_revertsAtQueue]: ./queueBatch.t.sol#L547
[test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically]: ./queueBatch.t.sol#L243
[test_whenLiveBatchRead_returnsExactSubActionsAndRejectsInvalidIndex]: ./queueBatch.t.sol#L276
[test_whenQueuedConfigRead_returnsExactStateAndDefaults]: ./queueBatch.t.sol#L316
[test_givenDisabled_whenBatchQueued_reverts]: ./queueBatch.t.sol#L692
[test_givenPolicyInactive_whenBatchQueued_reverts]: ./queueBatch.t.sol#L735
[test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch]: ./queueBatch.t.sol#L1227
[test_whenValidSizedBatchQueued_storesEveryActionAndGuard]: ./queueBatch.t.sol#L862
[test_whenEmptyBatchQueued_reverts]: ./queueBatch.t.sol#L782
[test_whenBatchExceedsMaximum_reverts]: ./queueBatch.t.sol#L930
[test_whenReachableAssetActionsShareKey_batchReverts]: ./queueBatch.t.sol#L585
[test_whenKnownUnauthorizedIdentitiesQueueBatch_reverts]: ./queueBatch.t.sol#L669
[test_givenUnauthorizedCaller_whenBatchQueued_reverts]: ./queueBatch.t.sol#L654
[test_whenMaximumBatchQueued]: ./queueBatch.t.sol#L841
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts]: ./queueRescuePendingPayout.t.sol#L351
[test_givenQueuedRoute_whenOtherAssetRouteQueued]: ./queueBatch.t.sol#L1028
[test_givenDisabled_whenBatchQueued_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1283
[test_givenDisabled_whenBatchQueued_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1288
[test_givenDisabled_whenBatchQueued_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1293
[test_givenPolicyInactive_whenBatchQueued_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1424
[test_givenPolicyInactive_whenBatchQueued_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1429
[test_givenPolicyInactive_whenBatchQueued_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1434
[test_givenOperatorRotated_whenBatchQueued_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1409
[test_givenOperatorRotated_whenBatchQueued_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1414
[test_givenOperatorRotated_whenBatchQueued_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1419
[test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_AdminOnlySeed]: ./queueBatch.t.sol#L1298
[test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1311
[test_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch_RolesOverlapSeed]: ./queueBatch.t.sol#L1324
[test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_AdminOnlySeed]: ./queueBatch.t.sol#L1373
[test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1385
[test_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically_RolesOverlapSeed]: ./queueBatch.t.sol#L1397
[test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_AdminOnlySeed]: ./queueBatch.t.sol#L1337
[test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1349
[test_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically_RolesOverlapSeed]: ./queueBatch.t.sol#L1361
[test_whenValidSizedBatchQueued_storesEveryActionAndGuard_AdminOnlySeed]: ./queueBatch.t.sol#L1712
[test_whenValidSizedBatchQueued_storesEveryActionAndGuard_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1723
[test_whenValidSizedBatchQueued_storesEveryActionAndGuard_RolesOverlapSeed]: ./queueBatch.t.sol#L1734
[test_whenMaximumBatchQueued_AdminOnlySeed]: ./queueBatch.t.sol#L1601
[test_whenMaximumBatchQueued_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1606
[test_whenMaximumBatchQueued_RolesOverlapSeed]: ./queueBatch.t.sol#L1611
[test_whenEmptyBatchQueued_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1496
[test_whenEmptyBatchQueued_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1501
[test_whenEmptyBatchQueued_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1506
[test_whenBatchExceedsMaximum_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1481
[test_whenBatchExceedsMaximum_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1486
[test_whenBatchExceedsMaximum_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1491
[test_whenFirstActionTargetOrSelectorUnsupported_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1511
[test_whenFirstActionTargetOrSelectorUnsupported_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1526
[test_whenFirstActionTargetOrSelectorUnsupported_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1541
[test_whenLaterActionUnsupported_rollsBackEarlierKey_AdminOnlySeed]: ./queueBatch.t.sol#L1556
[test_whenLaterActionUnsupported_rollsBackEarlierKey_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1571
[test_whenLaterActionUnsupported_rollsBackEarlierKey_RolesOverlapSeed]: ./queueBatch.t.sol#L1586
[test_whenStaticPayloadLengthIsInvalid_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1673
[test_whenStaticPayloadLengthIsInvalid_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1686
[test_whenStaticPayloadLengthIsInvalid_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1699
[test_whenRoutePayloadEncodingIsInvalid_reverts_AdminOnlySeed]: ./queueBatch.t.sol#L1637
[test_whenRoutePayloadEncodingIsInvalid_reverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1649
[test_whenRoutePayloadEncodingIsInvalid_reverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1661
[test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_AdminOnlySeed]: ./queueBatch.t.sol#L1454
[test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1465
[test_whenAddressWordHasDirtyUpperBits_revertsAtQueue_RolesOverlapSeed]: ./queueBatch.t.sol#L1476
[test_whenReachableAssetActionsShareKey_batchReverts_AdminOnlySeed]: ./queueBatch.t.sol#L1616
[test_whenReachableAssetActionsShareKey_batchReverts_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1627
[test_whenReachableAssetActionsShareKey_batchReverts_RolesOverlapSeed]: ./queueBatch.t.sol#L1632
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_AdminOnlySeed]: ./queueRescuePendingPayout.t.sol#L1172
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_RevenueRoleOnlySeed]: ./queueRescuePendingPayout.t.sol#L1181
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts_RolesOverlapSeed]: ./queueRescuePendingPayout.t.sol#L1188
[test_givenQueuedRoute_whenOtherAssetRouteQueued_AdminOnlySeed]: ./queueBatch.t.sol#L1439
[test_givenQueuedRoute_whenOtherAssetRouteQueued_RevenueRoleOnlySeed]: ./queueBatch.t.sol#L1444
[test_givenQueuedRoute_whenOtherAssetRouteQueued_RolesOverlapSeed]: ./queueBatch.t.sol#L1449
[test_givenPolicyInactive_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1745
[test_givenActiveDisabled_givenBrokenRoles_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1774
[test_givenUnauthorizedCaller_givenBrokenTarget_whenQueueRequested_reverts]: ./queueBatch.t.sol#L1794
[test_givenDisabled_whenEmptyBatchQueued_reverts]: ./queueBatch.t.sol#L798
[test_givenInactive_whenEmptyBatchQueued_reverts]: ./queueBatch.t.sol#L815
[test_givenDisabled_whenBatchExceedsMaximum_reverts]: ./queueBatch.t.sol#L955
[test_givenInactive_whenBatchExceedsMaximum_reverts]: ./queueBatch.t.sol#L975

[test_givenTwoDifferentAssetRoutes_whenBatchExecutes]: ./queueBatch.t.sol#L1093

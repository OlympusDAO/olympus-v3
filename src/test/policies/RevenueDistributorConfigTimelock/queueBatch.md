# queueBatch scenario plan

Scope: RDT batching, selector/payload validation and conflict-key acquisition. Selector-specific downstream behavior belongs to each queue plan; execution order and atomicity belong to [executeQueuedAction](./executeQueuedAction.md).

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT enabled, RDT Kernel-active, selected as RD configOperator, permitted proposer, RD Kernel-active and locally enabled. Error order follows that list; guard errors are NotEnabled(), RevenueDistributorConfigTimelock_PolicyInactive(RDT/RD), ConfigOperator_Unauthorized(RDT), NotAuthorised(). Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Batch bounds 1..15 inclusive; each supported action has one key. Route/retirement/surplus-rescue/pending-rescue for the same asset share one key; yield selection uses a separate global key. Surplus requires NeverListed, while pending debt requires an asset that has been managed, so both rescue previews cannot simultaneously be valid for one asset. Across separate queued actions, an Admin can list/fund a formerly NeverListed asset while its old surplus action owns the key; a newly valid pending request then fails with ConfigKeyPending. Rescue selectors have their own preview/lifecycle rules documented in their plans.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | RDT state | Operator binding | RD state | Batch | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-A01 | Unauthorized caller, fuzz | Active/enabled | Selected | Active/enabled | Nonempty supported action | NotAuthorised() | Queue unchanged | Covered: [excluded authorized roles][test_givenUnauthorizedCaller_whenBatchQueued_reverts], [known identities][test_whenKnownUnauthorizedIdentitiesQueueBatch_reverts] |

## Lifecycle

| ID | Caller | RDT Kernel | RDT local | Selected operator | RD state | Batch | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-L01 | Each permitted proposer | Active | Disabled | Yes | Active/enabled | Valid nonempty | NotEnabled() | Queue unchanged | Covered: [both roles and rollback][testFuzz_givenDisabled_whenBatchQueued_reverts] |
| BATCH-L02 | Each permitted proposer | Inactive | Enabled | Yes | Active/enabled | Valid nonempty | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Queue unchanged | Covered: [both roles and rollback][testFuzz_givenPolicyInactive_whenBatchQueued_reverts] |
| BATCH-L03 | Each permitted proposer | Active | Enabled | No | Active/enabled | Valid nonempty | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [evidence][testFuzz_givenOperatorRotated_whenBatchQueued_reverts] |

## Downstream lifecycle

| ID | Caller | RD Kernel | RD local | First action | Later action | Asset-key relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-P02 | Each permitted proposer | Active | Disabled | Valid rescue | Valid rescue | Independent assets | Rescue-only batch queues | No payment at queue | Covered: [both roles and mixed surplus/pending rescue][testFuzz_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch] |
| BATCH-I07 | Each permitted proposer | Active | Disabled | Valid rescue | Route update | Independent valid keys | NotEnabled() | Entire batch and prior key acquisition roll back | Covered: [evidence][testFuzz_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically] |
| BATCH-I08 | Each permitted proposer | Active | Disabled | Valid rescue | Route retirement | Independent valid keys | NotEnabled() | Entire batch and prior key acquisition roll back | Covered: [evidence][testFuzz_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically] |
| BATCH-I09 | Each permitted proposer | Active | Disabled | Valid rescue | Yield-recipient update | Independent valid keys | NotEnabled() | Entire batch and prior key acquisition roll back | Covered: [evidence][testFuzz_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically] |

## Batch size

| ID | Caller | Batch length | Action validity | Key relationship | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-P01 | Each permitted proposer | Fuzz 1..15; seed 1,2,15 | All valid | Independent | Success | Exact ordered sub-actions, all keys/hashes; next ID increments once | Covered: [size fuzz, both roles and exact stored state][testFuzz_whenValidSizedBatchQueued_storesEveryActionAndGuard], [maximum seed][test_whenMaximumBatchQueued] |

## Invalid batch size

| ID | Caller | Batch length | Action validity | Common lifecycle | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BATCH-I01 | Each permitted proposer | 0 | N/A | Fuzz valid/failing | ITimelockBatchQueue_BatchEmpty() before lifecycle checks | Queue unchanged | Covered: [both roles, lifecycle precedence and rollback][testFuzz_whenEmptyBatchQueued_reverts] |
| BATCH-I10 | Each permitted proposer | 16 | Otherwise valid | Fuzz valid/failing | ITimelockBatchQueue_BatchTooLarge(16, 15) before lifecycle checks | Queue unchanged | Covered: [both roles, lifecycle precedence and rollback][testFuzz_whenBatchExceedsMaximum_reverts] |

## Target and selector inputs

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| BATCH-I02 | Each permitted proposer | Unsupported target at first position | RevenueDistributorConfigTimelock_InvalidAction(target, selector) | Queue and next ID unchanged | Covered: [evidence][testFuzz_whenFirstActionTargetOrSelectorUnsupported_reverts] |
| BATCH-I11 | Each permitted proposer | Unsupported selector for RD at first position | RevenueDistributorConfigTimelock_InvalidAction(target, selector) | Queue and next ID unchanged | Covered: [evidence][testFuzz_whenFirstActionTargetOrSelectorUnsupported_reverts] |
| BATCH-I12 | Each permitted proposer | Unsupported target or selector after a valid action | RevenueDistributorConfigTimelock_InvalidAction(target, selector) | Rollback all earlier key acquisitions and ID | Covered: [evidence][testFuzz_whenLaterActionUnsupported_rollsBackEarlierKey] |

## Payload inputs

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| BATCH-I03 | Each permitted proposer | Static disable/yield length not 32; surplus length not 64; pending-rescue length not 128; truncated/trailing word | RevenueDistributorConfigTimelock_InvalidAction(target,selector) | Queue unchanged | Covered: [all selectors, both roles, first/later position and truncated/trailing payloads][testFuzz_whenStaticPayloadLengthIsInvalid_reverts] |
| QBATCH-V01 | Each permitted proposer; any getter caller, fuzz | Successfully queued live batch; sub-action index=length or MAX | ITimelockBatchQueue_SubActionIndexOutOfBounds(id,index,length) | Read only; valid 0..length-1 indexes return exact supplied actions | Covered: [evidence][testFuzz_whenLiveBatchRead_returnsExactSubActionsAndRejectsInvalidIndex] |
| QBATCH-V02 | Each permitted proposer; any getter caller, fuzz | Live batch, unknown ID, or cleared configuration slot; key index=count or MAX | IConfigTimelockBatchQueue_ConfigStateIndexOutOfBounds(id,subIndex,keyIndex,count) | Read only; valid indexes expose independently expected keys/hashes | Covered: [evidence][testFuzz_whenQueuedConfigRead_returnsExactStateAndDefaults] |
| BATCH-I04 | Each permitted proposer | setAssetRoutes missing its dynamic offset, or decodable but noncanonical shifted offsets/trailing bytes | Raw ABI decode failure for the missing offset; decodable noncanonical gives InvalidAction(target,selector) | Queue unchanged | Covered: [both roles and malformed forms][testFuzz_whenRoutePayloadEncodingIsInvalid_reverts] |
| BATCH-I05 | Each permitted proposer | Dirty upper bits in the first address word of route, retirement, yield, surplus-rescue or pending-rescue payload | Solidity ABI decode failure at queue time | Queue unchanged; no target effect or queue ownership | Covered: [all supported selectors and both roles][testFuzz_whenAddressWordHasDirtyUpperBits_revertsAtQueue] |

## Key conflicts

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDT-Q02 | Each permitted proposer | Same key already queued, or twice in batch; route/retire/pending-rescue pairs on a managed asset with valid previews; surplus/surplus on a NeverListed asset. Exclude same-batch surplus/pending pair | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | Atomic queue rollback | Covered: [reachable in-batch selector pairs][testFuzz_whenReachableAssetActionsShareKey_batchReverts], [existing owner][test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts] |
| BATCH-Q02 | Each permitted proposer | Actions use distinct asset keys | Success | Independent keys queue; no RD changes at queue | Covered: [independent ownership and no queue-time change][test_givenQueuedRoute_whenOtherAssetRouteQueued] |
| RDT-Q03 | Each permitted proposer | One asset action and one global yield action | Success | Independent keys queue; no RD changes at queue | Covered: [asset and global metadata][test_givenIndependentAssetAndGlobalAction_whenQueued] |
| BATCH-Q04 | Each permitted proposer | Two global yield actions | IConfigTimelockBatchQueue_ConfigKeyPending(globalKey, ownerId) | Atomic queue rollback | Covered: [evidence][testFuzz_whenTwoYieldActionsShareGlobalKey_batchReverts] |

[testFuzz_givenOperatorRotated_whenBatchQueued_reverts]: ./queueBatch.t.sol
[testFuzz_givenDistributorDisabled_whenRescuePrecedesRoute_batchRevertsAtomically]: ./queueBatch.t.sol
[testFuzz_whenFirstActionTargetOrSelectorUnsupported_reverts]: ./queueBatch.t.sol
[testFuzz_whenLaterActionUnsupported_rollsBackEarlierKey]: ./queueBatch.t.sol
[testFuzz_whenStaticPayloadLengthIsInvalid_reverts]: ./queueBatch.t.sol
[testFuzz_whenRoutePayloadEncodingIsInvalid_reverts]: ./queueBatch.t.sol
[testFuzz_whenAddressWordHasDirtyUpperBits_revertsAtQueue]: ./queueBatch.t.sol
[testFuzz_whenTwoYieldActionsShareGlobalKey_batchReverts]: ./queueBatch.t.sol
[testFuzz_givenDistributorDisabled_whenRescuePrecedesExistingConfig_batchRevertsAtomically]: ./queueBatch.t.sol
[testFuzz_whenLiveBatchRead_returnsExactSubActionsAndRejectsInvalidIndex]: ./queueBatch.t.sol
[testFuzz_whenQueuedConfigRead_returnsExactStateAndDefaults]: ./queueBatch.t.sol
[testFuzz_givenDisabled_whenBatchQueued_reverts]: ./queueBatch.t.sol
[testFuzz_givenPolicyInactive_whenBatchQueued_reverts]: ./queueBatch.t.sol
[testFuzz_givenDistributorDisabled_whenPermittedCallerQueuesRescueBatch]: ./queueBatch.t.sol
[testFuzz_whenValidSizedBatchQueued_storesEveryActionAndGuard]: ./queueBatch.t.sol
[testFuzz_whenEmptyBatchQueued_reverts]: ./queueBatch.t.sol
[testFuzz_whenBatchExceedsMaximum_reverts]: ./queueBatch.t.sol
[testFuzz_whenReachableAssetActionsShareKey_batchReverts]: ./queueBatch.t.sol
[test_whenKnownUnauthorizedIdentitiesQueueBatch_reverts]: ./queueBatch.t.sol#L679

[test_givenUnauthorizedCaller_whenBatchQueued_reverts]: ./queueBatch.t.sol#L664
[test_whenMaximumBatchQueued]: ./queueBatch.t.sol#L802
[test_givenAssetKeyOwned_whenAnotherValidRequestQueues_reverts]: ./queueRescuePendingPayout.t.sol#L327
[test_givenQueuedRoute_whenOtherAssetRouteQueued]: ./queueBatch.t.sol#L1129
[test_givenIndependentAssetAndGlobalAction_whenQueued]: ./queueRescuePendingPayout.t.sol#L365

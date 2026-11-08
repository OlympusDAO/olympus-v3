# queueSetYieldRecipient scenario plan

Queue admission requires own Kernel activity, then local enablement, then an accepted proposer role. Bounds, target metadata and action validation follow. Rejected admission preserves IDs, keys, payloads, custody and committed logs.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: RDT wrapper for RD.setYieldRecipient(recipient). Store the requested global yieldRecipient. Queueing validates the candidate against current RD state, and execution revalidates live conditions after its state-hash guard.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, REVENUE_DISTRIBUTOR_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT Kernel-active, RDT enabled, permitted proposer, selected as RD configOperator, RD Kernel-active and locally enabled. Error order follows that list: own RevenueDistributorConfigTimelock_PolicyNotActive(RDT), NotEnabled(), NotAuthorised(), then selected-operator and target checks. Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: global yield-recipient; expected hash: keccak256(abi.encode(current yieldRecipient, current configOperator)).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `recipient_` against the complete downstream candidate matrix in [setYieldRecipient](../RevenueDistributor/setYieldRecipient.md). This wrapper uses valid, zero and one representative invalid candidate to prove queue-time rejection, then separately covers candidate and route drift after a valid queue.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and `recipient_` domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSYR-A01 | Fuzz callers excluding every ADMIN_ROLE and REVENUE_DISTRIBUTOR_ADMIN_ROLE holder | All earlier RDT/operator gates and RD lifecycle valid; fuzz `recipient_` as zero, Treasury, valid policy, EOA, incompatible contract, inactive policy and disabled policy | NotAuthorised() | Queue unchanged | Covered: [evidence][test_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle

Fuzz the current pointer and `recipient_` across the authorization domain above; neither affects these guard outcomes.

| ID | Caller | Local active | Local enabled | Selected operator | Distributor active | Distributor enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-L01 | Fuzz permitted role caller | true | false | Yes | true | true | NotEnabled() | Queue unchanged | Covered: [roles, pointer and candidate fuzz][test_givenTimelockDisabled_whenQueued_reverts] |
| QSYR-L02 | Fuzz permitted role caller | false | true | Yes | true | true | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Queue unchanged | Covered: [roles, pointer and candidate fuzz][test_givenTimelockInactive_whenQueued_reverts] |
| QSYR-L03 | Fuzz permitted role caller | true | true | No | true | true | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [roles, pointer and candidate fuzz][test_givenOperatorRotated_whenQueued_reverts] |
| QSYR-L04 | Fuzz permitted role caller | true | true | Yes | true | false | PolicyDependency_NotActive(RD) | Queue unchanged | Covered: [roles, pointer and candidate fuzz][test_givenDistributorDisabled_whenQueued_reverts] |
| QSYR-L05 | Fuzz permitted role caller | true | true | Yes | false | true | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_AdminOnlySeed], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RevenueRoleOnlySeed], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RolesOverlapSeed] |
| QSYR-L06 | Fuzz permitted role caller | true | true | Yes | false | false | PolicyDependency_NotActive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_AdminOnlySeed], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RevenueRoleOnlySeed], [test][test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RolesOverlapSeed] |

## Behavior

| ID | Caller | Current pointer | `recipient_` | Candidate state | Active repurchase routes | Pending yield assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-P01 | Fuzz permitted role caller | Different value | Nonzero policy | Active/enabled, interface-compatible | All supported by candidate | All supported by candidate | Queue then ready execution succeeds | Exact forwarding; getter and role entitlement move to candidate | Covered: [test][test_whenValidNonzeroRecipientQueues_executesAfterDelay], [test][test_whenValidNonzeroRecipientQueues_executesAfterDelay_AdminOnlySeed], [test][test_whenValidNonzeroRecipientQueues_executesAfterDelay_RevenueRoleOnlySeed], [test][test_whenValidNonzeroRecipientQueues_executesAfterDelay_RolesOverlapSeed], [operator commitment and restoration][test_whenQueuedConfiguration_commitsCurrentOperatorAndRestorationExecutes] |
| QSYR-P02 | Fuzz permitted role caller | Nonzero | Zero | N/A | None positive | Fuzz none/one/multiple | Queue then ready execution succeeds | Exact forwarding; getter clears and yield entitlement follows Treasury fallback | Covered: [test][test_whenNonzeroPointerCleared_executes], [test][test_whenNonzeroPointerCleared_executes_AdminOnlySeed], [test][test_whenNonzeroPointerCleared_executes_RevenueRoleOnlySeed], [test][test_whenNonzeroPointerCleared_executes_RolesOverlapSeed] |
| QSYR-P03 | Fuzz permitted role caller | Same nonzero policy | Same nonzero policy | Not probed | All remain supported | All remain supported | Queue reverts with RevenueDistributor_SameAddress(candidate) | No action ID consumed, key acquired or events emitted | Covered: [test][test_whenSameNonzeroRecipientQueues_reverts], [test][test_whenSameNonzeroRecipientQueues_reverts_AdminOnlySeed], [test][test_whenSameNonzeroRecipientQueues_reverts_RevenueRoleOnlySeed], [test][test_whenSameNonzeroRecipientQueues_reverts_RolesOverlapSeed] |
| QSYR-P04 | Fuzz permitted role caller | Zero | Zero | N/A | None positive | Fuzz none/one/multiple | Queue reverts with RevenueDistributor_SameAddress(address(0)) | No action ID consumed, key acquired or events emitted | Covered: [test][test_whenZeroRecipientQueues_reverts], [test][test_whenZeroRecipientQueues_reverts_AdminOnlySeed], [test][test_whenZeroRecipientQueues_reverts_RevenueRoleOnlySeed], [test][test_whenZeroRecipientQueues_reverts_RolesOverlapSeed] |

## Invalid inputs

| ID | Caller | Current pointer | `recipient_` | Candidate state | Route/pending compatibility | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-I01 | Fuzz permitted role caller | Any different value | Current Treasury | Otherwise valid contract | Irrelevant; identity check first | Queue gives RevenueDistributor_InvalidYieldRecipient(Treasury) | No action ID consumed or key acquired; pointer and route state unchanged | Covered: [test][test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue], [test][test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_AdminOnlySeed], [test][test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RevenueRoleOnlySeed], [test][test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RolesOverlapSeed] |

## State changes

| ID | Caller | Pointer after queue | Candidate policy after queue | Configured-recipient collision | Repurchase support | Pending-yield support | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-S01 | Fuzz permitted role caller | Changed | Valid | None | Compatible | Compatible | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key/action | Covered: [test][test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey], [test][test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_AdminOnlySeed], [test][test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RevenueRoleOnlySeed], [test][test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RolesOverlapSeed] |
| QSYR-S02 | Fuzz permitted role caller | Unchanged | Locally disabled | None | Any | Any | Hash remains valid; RD gives PolicyDependency_NotActive(candidate) | Atomic downstream failure; re-enable candidate to retry | Covered: [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_AdminOnlySeed], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RevenueRoleOnlySeed], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RolesOverlapSeed] |
| QSYR-S04 | Fuzz permitted role caller | Unchanged | Kernel-inactive | None | Any | Any | Hash remains valid; RD gives PolicyDependency_NotActive(candidate) | Atomic downstream failure; reactivate candidate to retry | Covered: [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_AdminOnlySeed], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RevenueRoleOnlySeed], [test][test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RolesOverlapSeed] |
| QSYR-S05 | Fuzz permitted role caller | Unchanged | Valid | Added for candidate | Compatible | Compatible | Hash remains valid; RD gives RevenueDistributor_DuplicateRecipient(candidate) | Atomic downstream failure; remove collision to retry | Covered: [test][test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries], [test][test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_AdminOnlySeed], [test][test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RevenueRoleOnlySeed], [test][test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RolesOverlapSeed] |
| QSYR-S03 | Fuzz permitted role caller | Unchanged | Valid | None | New positive route unsupported by candidate | Compatible | Hash remains valid; execution gives RevenueDistributor_YieldRecipientUnavailable(candidate, asset) | Pointer, debts and target state unchanged; retain action/key | Covered: [test][test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts], [test][test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_AdminOnlySeed], [test][test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RevenueRoleOnlySeed], [test][test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RolesOverlapSeed] |
| QSYR-S06 | Fuzz permitted role caller | Unchanged | Valid | None | Compatible | New Retired pending-yield asset unsupported | Hash remains valid; execution gives RevenueDistributor_YieldRecipientUnavailable(candidate, asset) | Pointer, debts and target state unchanged; retain action/key | Covered: [test][test_whenUnsupportedRetiredPendingYieldAdded_executionReverts], [test][test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_AdminOnlySeed], [test][test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RevenueRoleOnlySeed], [test][test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RolesOverlapSeed] |

## Queue conflicts

| ID | Caller | Queue conflict / action input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSYR-Q01 | Fuzz permitted role caller | Conflict with existing global yield-recipient action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [test][test_whenGlobalKeyAlreadyOwned_secondQueueReverts], [test][test_whenGlobalKeyAlreadyOwned_secondQueueReverts_AdminOnlySeed], [test][test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RevenueRoleOnlySeed], [test][test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RolesOverlapSeed] |

[test_whenUnauthorizedCallerQueues_reverts]: ./queueSetYieldRecipient.t.sol#L88
[test_givenTimelockDisabled_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol#L116
[test_givenTimelockInactive_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol#L135
[test_givenOperatorRotated_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol#L161
[test_givenDistributorDisabled_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol#L186
[test_givenDistributorInactive_whenQueued_revertsBeforeLocalState]: ./queueSetYieldRecipient.t.sol#L210
[test_whenValidNonzeroRecipientQueues_executesAfterDelay]: ./queueSetYieldRecipient.t.sol#L241
[test_whenNonzeroPointerCleared_executes]: ./queueSetYieldRecipient.t.sol#L325
[test_whenSameNonzeroRecipientQueues_reverts]: ./queueSetYieldRecipient.t.sol#L368
[test_whenZeroRecipientQueues_reverts]: ./queueSetYieldRecipient.t.sol#L289
[test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue]: ./queueSetYieldRecipient.t.sol#L62
[test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueSetYieldRecipient.t.sol#L419
[test_whenCandidateBecomesUnavailable_executionRevertsThenRetries]: ./queueSetYieldRecipient.t.sol#L486
[test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries]: ./queueSetYieldRecipient.t.sol#L525
[test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts]: ./queueSetYieldRecipient.t.sol#L557
[test_whenUnsupportedRetiredPendingYieldAdded_executionReverts]: ./queueSetYieldRecipient.t.sol#L593
[test_whenGlobalKeyAlreadyOwned_secondQueueReverts]: ./queueSetYieldRecipient.t.sol#L455
[test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L635
[test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L650
[test_givenDistributorInactive_whenQueued_revertsBeforeLocalState_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L665
[test_whenValidNonzeroRecipientQueues_executesAfterDelay_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L965
[test_whenValidNonzeroRecipientQueues_executesAfterDelay_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L977
[test_whenValidNonzeroRecipientQueues_executesAfterDelay_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L989
[test_whenNonzeroPointerCleared_executes_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L788
[test_whenNonzeroPointerCleared_executes_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L800
[test_whenNonzeroPointerCleared_executes_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L812
[test_whenSameNonzeroRecipientQueues_reverts_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L860
[test_whenSameNonzeroRecipientQueues_reverts_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L865
[test_whenSameNonzeroRecipientQueues_reverts_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L870
[test_whenZeroRecipientQueues_reverts_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L1001
[test_whenZeroRecipientQueues_reverts_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L1006
[test_whenZeroRecipientQueues_reverts_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L1011
[test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L875
[test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L885
[test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L890
[test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L824
[test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L836
[test_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L848
[test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L716
[test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L729
[test_whenCandidateBecomesUnavailable_executionRevertsThenRetries_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L742
[test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L680
[test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L692
[test_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L704
[test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L895
[test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L907
[test_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L919
[test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L931
[test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L941
[test_whenUnsupportedRetiredPendingYieldAdded_executionReverts_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L953
[test_whenGlobalKeyAlreadyOwned_secondQueueReverts_AdminOnlySeed]: ./queueSetYieldRecipient.t.sol#L755
[test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RevenueRoleOnlySeed]: ./queueSetYieldRecipient.t.sol#L766
[test_whenGlobalKeyAlreadyOwned_secondQueueReverts_RolesOverlapSeed]: ./queueSetYieldRecipient.t.sol#L777

[test_whenQueuedConfiguration_commitsCurrentOperatorAndRestorationExecutes]: ./queueSetYieldRecipient.t.sol#L1016

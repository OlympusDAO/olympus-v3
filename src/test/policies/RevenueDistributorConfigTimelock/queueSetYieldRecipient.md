# queueSetYieldRecipient scenario plan

Scope: RDT wrapper for RD.setYieldRecipient(recipient). Store the requested global yieldRecipient. Queueing validates the candidate against current RD state, and execution revalidates live conditions after its state-hash guard.

Co-located queue getters: record nextActionId before queue; on success it increments exactly once. Check getQueuedAction proposer, ready/expiry, flags and payload hash; getQueuedActionLength/getQueuedSubAction expose the exact ordered inputs. For each sub-action, verify getQueuedConfigStateCount, getQueuedConfigDestination, getQueuedConfigState and pendingActionId against independently computed destination/key/hash. Rejected queues preserve ID, existing metadata and keys. Getter callers are permissionless, including while RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

RDT = Revenue Distributor Config Timelock; RD = RevenueDistributor. Proposers are Admin or Revenue Distributor Admin, separately. Successful queue gates: RDT enabled, RDT Kernel-active, selected as RD configOperator, permitted proposer, RD Kernel-active and locally enabled. Error order follows that list; guard errors are NotEnabled(), RevenueDistributorConfigTimelock_PolicyInactive(RDT/RD), ConfigOperator_Unauthorized(RDT), NotAuthorised(). Generic timing/cancellation is owned by executeQueuedAction/cancelQueuedAction plans. Key: global yield-recipient; expected hash: keccak256(abi.encode(current yieldRecipient)).

Fuzz permitted proposers across Admin and Revenue Distributor Admin for every non-authorization row. Queueing validates `recipient_` against the complete downstream candidate matrix in [setYieldRecipient](../RevenueDistributor/setYieldRecipient.md). This wrapper uses valid, zero and one representative invalid candidate to prove queue-time rejection, then separately covers candidate and route drift after a valid queue.

Queue success: exact target/selector/ABI payload, proposer, ID, queuedAt/ready/expiry, scoped conflict key and independently computed expected-state hash; one TimelockSubActionQueued then one TimelockActionQueued; no configuration or token movement. Failed queue: ID, keys, stored actions and RD state unchanged; no committed events. At a ready timestamp, verify exact forwarding and downstream configuration effect; failed execution retains action/key and rolls back target state.

## Authorization

| ID | Caller | Queue prerequisites and `recipient_` domain | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSYR-A01 | Any caller outside the permitted proposer set, fuzz | All earlier RDT/operator gates and RD lifecycle valid; fuzz `recipient_` as zero, Treasury, valid policy, EOA, incompatible contract, inactive policy and disabled policy | NotAuthorised() | Queue unchanged | Covered: [evidence][testFuzz_whenUnauthorizedCallerQueues_reverts] |

## Lifecycle

Fuzz the current pointer and `recipient_` across the authorization domain above; neither affects these guard outcomes.

| ID | RDT Kernel | RDT local | Selected operator | RD Kernel | RD local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-L01 | Active | Disabled | Yes | Active | Enabled | NotEnabled() | Queue unchanged | Covered: [roles, pointer and candidate fuzz][testFuzz_givenTimelockDisabled_whenQueued_reverts] |
| QSYR-L02 | Inactive | Enabled | Yes | Active | Enabled | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Queue unchanged | Covered: [roles, pointer and candidate fuzz][testFuzz_givenTimelockInactive_whenQueued_reverts] |
| QSYR-L03 | Active | Enabled | No | Active | Enabled | ConfigOperator_Unauthorized(RDT) | Queue unchanged | Covered: [roles, pointer and candidate fuzz][testFuzz_givenOperatorRotated_whenQueued_reverts] |
| QSYR-L04 | Active | Enabled | Yes | Active | Disabled | NotEnabled() | Queue unchanged | Covered: [roles, pointer and candidate fuzz][testFuzz_givenDistributorDisabled_whenQueued_reverts] |
| QSYR-L05 | Active | Enabled | Yes | Inactive | Enabled or disabled | RevenueDistributorConfigTimelock_PolicyInactive(RD) | Queue unchanged; RD activity precedes RD local state | Covered: [roles, local states, pointer and candidate fuzz][testFuzz_givenDistributorInactive_whenQueued_revertsBeforeLocalState] |

## Behavior

| ID | Caller | Current pointer | `recipient_` | Candidate state | Active repurchase routes | Pending yield assets | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-P01 | Permitted proposer, fuzz | Different value | Nonzero policy | Active/enabled, interface-compatible | All supported by candidate | All supported by candidate | Queue then ready execution succeeds | Exact forwarding; getter and role entitlement move to candidate | Covered: [active and pending asset cardinalities][testFuzz_whenValidNonzeroRecipientQueues_executesAfterDelay] |
| QSYR-P02 | Permitted proposer, fuzz | Nonzero | Zero | N/A | None positive | Fuzz none/one/multiple | Queue then ready execution succeeds | Exact forwarding; getter clears and yield entitlement follows Treasury fallback | Covered: [pending asset cardinalities][testFuzz_whenNonzeroPointerCleared_executes] |
| QSYR-P03 | Permitted proposer, fuzz | Same nonzero policy | Same nonzero policy | Revalidated as active/enabled and interface-compatible | All remain supported | All remain supported | Queue and ready execution succeed; RD call is a validated no-op | Timelock execution events only; no YieldRecipientSet or target-state change | Covered: [active and pending asset cardinalities][testFuzz_whenSameNonzeroRecipientQueues_executesAsValidatedNoOp] |
| QSYR-P04 | Permitted proposer, fuzz | Zero | Zero | N/A | None positive | Fuzz none/one/multiple | Queue and ready execution succeed; RD call is a validated no-op | Timelock execution events only; no YieldRecipientSet or target-state change | Covered: [pending asset cardinalities][testFuzz_whenZeroRecipientQueues_executes] |

## Invalid inputs

| ID | Caller | Current pointer | `recipient_` | Candidate state | Route/pending compatibility | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-I01 | Admin; Revenue Distributor Admin separately | Any different value | Current Treasury | Otherwise valid contract | Irrelevant; identity check first | Queue gives RevenueDistributor_InvalidYieldRecipient(Treasury) | No action ID consumed or key acquired; pointer and route state unchanged | Covered: [evidence][test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue] |

## State changes

| ID | Caller | Pointer after queue | Candidate policy after queue | Configured-recipient collision | Repurchase support | Pending-yield support | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| QSYR-S01 | Admin; Revenue Distributor Admin separately | Changed | Valid | None | Compatible | Compatible | IConfigTimelockBatchQueue_ConfigStateChanged | Failed execution retains key/action | Covered: [evidence][testFuzz_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey] |
| QSYR-S02 | Admin; Revenue Distributor Admin separately | Unchanged | Locally disabled | None | Any | Any | Hash remains valid; RD gives RevenueDistributor_InvalidYieldRecipient(candidate) | Atomic downstream failure; re-enable candidate to retry | Covered: [evidence][testFuzz_whenCandidateBecomesUnavailable_executionRevertsThenRetries] |
| QSYR-S04 | Admin; Revenue Distributor Admin separately | Unchanged | Kernel-inactive | None | Any | Any | Hash remains valid; RD gives RevenueDistributor_InvalidYieldRecipient(candidate) | Atomic downstream failure; reactivate candidate to retry | Covered: [evidence][testFuzz_whenCandidateBecomesUnavailable_executionRevertsThenRetries] |
| QSYR-S05 | Admin; Revenue Distributor Admin separately | Unchanged | Valid | Added for candidate | Compatible | Compatible | Hash remains valid; RD gives RevenueDistributor_DuplicateRecipient(candidate) | Atomic downstream failure; remove collision to retry | Covered: [evidence][testFuzz_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries] |
| QSYR-S03 | Admin; Revenue Distributor Admin separately | Unchanged | Valid | None | New positive route unsupported by candidate | Compatible | Hash remains valid; execution gives RevenueDistributor_YieldRecipientUnavailable(candidate, asset) | Pointer, debts and target state unchanged; retain action/key | Covered: [evidence][testFuzz_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts] |
| QSYR-S06 | Admin; Revenue Distributor Admin separately | Unchanged | Valid | None | Compatible | New Retired pending-yield asset unsupported | Hash remains valid; execution gives RevenueDistributor_YieldRecipientUnavailable(candidate, asset) | Pointer, debts and target state unchanged; retain action/key | Covered: [evidence][testFuzz_whenUnsupportedRetiredPendingYieldAdded_executionReverts] |

## Queue conflicts

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| QSYR-Q01 | Each permitted proposer | Conflict with existing global yield-recipient action; same/different requested value | IConfigTimelockBatchQueue_ConfigKeyPending(key,ownerId) | No new ID consumed; existing action retained | Covered: [evidence][testFuzz_whenGlobalKeyAlreadyOwned_secondQueueReverts] |

[testFuzz_whenUnauthorizedCallerQueues_reverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_givenTimelockDisabled_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_givenTimelockInactive_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_givenOperatorRotated_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_givenDistributorDisabled_whenQueued_reverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_givenDistributorInactive_whenQueued_revertsBeforeLocalState]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenValidNonzeroRecipientQueues_executesAfterDelay]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenNonzeroPointerCleared_executes]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenSameNonzeroRecipientQueues_executesAsValidatedNoOp]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenZeroRecipientQueues_executes]: ./queueSetYieldRecipient.t.sol
[test_whenTreasuryQueuedAsYieldRecipient_revertsAtQueue]: ./queueSetYieldRecipient.t.sol#L60
[testFuzz_whenPointerChangesAfterQueue_executionRevertsAndRetainsKey]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenCandidateBecomesUnavailable_executionRevertsThenRetries]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenCandidateBecomesRouteRecipient_executionRevertsThenRetries]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenUnsupportedActiveRepurchaseRouteAdded_executionReverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenUnsupportedRetiredPendingYieldAdded_executionReverts]: ./queueSetYieldRecipient.t.sol
[testFuzz_whenGlobalKeyAlreadyOwned_secondQueueReverts]: ./queueSetYieldRecipient.t.sol

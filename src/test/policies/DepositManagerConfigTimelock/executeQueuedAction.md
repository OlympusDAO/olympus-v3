# DepositManagerConfigTimelock.executeQueuedAction coverage plan

Shared action existence, terminal-status and execution-window checks precede concrete admission. Execution then requires own Kernel activity before local enablement and target checks; its caller remains permissionless.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-EXECUTE`.

Execution is permissionless. A pending action executes only at T≤now≤E; T and E are inclusive.
Order: action existence → executed → cancelled → not-ready → expired → DMCT enabled
→ DMCT active → DM Kernel binding and membership → DM enabled → selected config operator
→ each destination/key/pre-state guard

Every pre-state includes current DM.configOperator() alongside the existing limits, withdrawal, or route fields. Live authority checks reject a lost selection before hash comparison. Restoration uses current-state matching and retains the original notice and expiry.
→ target dispatch. The executed flag is set before dispatch and rolls back with any failure.
Successful execution clears payloads, guards, destinations and key owners, while retaining
proposer/timestamps/terminal metadata. Generic corrupted-storage and changeable-destination
branches belong to the shared queue suite: this product has one immutable destination.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization and time

| ID | Caller | Action / timestamp | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-EXECUTE-A01 | Fuzz all callers | Pending; any time in inclusive execution window | Execute without an executor role | Covered: [test][test_givenWithinExecutionWindow_executes] |
| DMCT-EXECUTE-I01 | Fuzz all callers | Fuzz unknown uint64 IDs; explicit 0,MAX64 | ActionNotFound(id), before lifecycle/roles | Covered: [test][test_whenUnknownExecution_reverts], [test][test_whenUnknownExecutionBoundaryIds_reverts] |
| DMCT-EXECUTE-I02 | Any caller | Previously executed; DMCT now paused | ActionAlreadyExecuted(id) before local state | Covered: [test][test_givenExecuted_whenExecutedAgain_reverts] |
| DMCT-EXECUTE-I03 | Any caller | Cancelled action | ActionCancelled(id) before readiness | Covered: [test][test_givenCancelled_whenExecuted_reverts] |
| DMCT-EXECUTE-N01 | Any caller | Q≤now<T; exact T-1, including paused DMCT | ActionNotReady(id,T); retain pending state | Covered: [test][test_givenBeforeDelay_reverts], [test][test_givenPaused_whenExecutionJustBeforeReady_reverts] |
| DMCT-EXECUTE-N02 | Any caller | T,T+1,E-1,E | Execute and release keys at all four boundary seeds | Covered: [test][test_whenExecutionAtReady], [test][test_whenExecutionJustAfterReady], [test][test_whenExecutionJustBeforeExpiry], [test][test_whenExecutionAtExpiry] |
| DMCT-EXECUTE-N03 | Any caller | Fuzz E+1..MAX256 | ActionExpired(id,E); retain pending state | Covered: [test][test_whenExecutionAfterExpiry_reverts] |

## Lifecycle and binding

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-EXECUTE-L01 | Any | true | false | true | true | NotEnabled() | Covered: [test][test_givenTimelockIsDisabled_reverts] |
| DMCT-EXECUTE-L02 | Any | true | true | true | false | NotEnabled() | Covered: [test][test_givenDepositManagerIsDisabled_reverts] |
| DMCT-EXECUTE-L03 | Any | false | true | true | true | DepositManagerConfigTimelock_PolicyInactive(DMCT) | Covered: [test][test_givenTimelockPolicyIsInactive_reverts] |
| DMCT-EXECUTE-L04 | Any | true | true | false | true | PolicyDependency_NotActive(DM) | Covered: [test][test_givenDepositManagerPolicyIsInactive_reverts] |
| DMCT-EXECUTE-L05 | Any | true | true | true | true | After Kernel reactivation, pending action executes | Covered: [test][test_givenPoliciesAreReactivated_executes] |
| DMCT-EXECUTE-D01 | Any | true | true | true | true | Operator changed away: ConfigOperator_Unauthorized(DMCT) | Covered: [test][test_givenConfigOperatorChanged_executionReverts] |
| DMCT-EXECUTE-D02 | Any | true | true | true | true | Operator rotated away; execution rejected with pending intent retained; restore operator and execute within fuzzed original inclusive window | Covered: [test][test_givenConfigOperatorChangedAwayAndBack_executionSucceeds] |

## Execution, cleanup and failures

| ID | Caller | Action / drift | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-EXECUTE-P01 | Any | DMCT paused and re-enabled before queue | Queue and execute normally after recovery | Covered: [test][test_givenTimelockIsReEnabled_queuesAndExecutes] |
| DMCT-EXECUTE-P02 | Fuzz all callers | Singleton cap | Exact target/sub-action/action events; executed=true; payload/guards/destination/key cleared; metadata retained; same key requeueable | Covered: [test][test_whenExecuted_emitsExactEventsAndReleasesState] |
| DMCT-EXECUTE-P03 | Any | Queued cap equals current cap | Execute delayed no-op and release key | Covered: [test][test_whenCapUnchanged_executesAndReleasesKey] |
| DMCT-EXECUTE-P04 | Fuzz all callers | Route creation, followed by disabling another route | Both dispatches apply atomically; new route enabled, old route disabled | Covered: [test][test_givenBatchWithRouteCreation_whenMatured_permissionlessExecutionIsAtomic] |
| DMCT-EXECUTE-D03 | Any | Creation operator role revoked | ConfigStateChanged with role-sensitive current hash; no route created | Covered: [test][test_givenQueuedRoute_whenOperatorRoleRevoked_revertsAsStale] |
| DMCT-EXECUTE-D04 | Any | Creation operator role revoked then regranted | Original pre-state restored; route creates normally | Covered: [test][test_givenQueuedRoute_whenOperatorRoleRevokedAndRegranted_succeeds] |
| DMCT-EXECUTE-D05 | Any | Admin created queued route directly | ConfigStateChanged; no duplicate receipt-token registration | Covered: [test][test_givenQueuedRoute_whenAdminCreatesDirectly_revertsAsStale] |
| DMCT-EXECUTE-D06 | Any | Manager reports a foreign Kernel and is paused | PolicyDependency_KernelMismatch(DM,expectedKernel,reportedKernel) before readiness; action/key remain pending | Covered: [test][test_givenForeignKernelAndPausedManager_whenExecuted_reverts] |
| DMCT-EXECUTE-D07 | Any | Manager enabled-state getter reverts | PolicyDependency_InvalidDependency(DM); action/key remain pending | Covered: [test][test_givenManagerStatusGetterReverts_whenExecuted_reverts] |
| DMCT-EXECUTE-D08 | Any | Manager enabled-state getter returns malformed ABI | PolicyDependency_InvalidDependency(DM); action/key remain pending | Covered: [test][test_givenManagerStatusMalformed_whenExecuted_reverts] |
| DMCT-EXECUTE-T01 | Any | Target setter reverts after admission | Exact dependency revert; executed flag, queue/key and target state roll back | Covered: [test][test_whenTargetSetterReverts_revertsAtomically] |
| DMCT-EXECUTE-T02 | Any | Later batch sub-action stale | Roll back earlier route creation and receipt-token registration | Covered: [test][test_givenBatchWithRouteCreation_whenLaterActionIsStale_rollsBackCreation] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenWithinExecutionWindow_executes]: ./execute.t.sol#L245
[test_whenUnknownExecution_reverts]: ./execute.t.sol#L431
[test_whenUnknownExecutionBoundaryIds_reverts]: ./execute.t.sol#L443
[test_givenExecuted_whenExecutedAgain_reverts]: ./execute.t.sol#L461
[test_givenCancelled_whenExecuted_reverts]: ./execute.t.sol#L476
[test_givenBeforeDelay_reverts]: ./execute.t.sol#L228
[test_givenPaused_whenExecutionJustBeforeReady_reverts]: ./execute.t.sol#L510
[test_whenExecutionAtReady]: ./execute.t.sol#L490
[test_whenExecutionJustAfterReady]: ./execute.t.sol#L495
[test_whenExecutionJustBeforeExpiry]: ./execute.t.sol#L500
[test_whenExecutionAtExpiry]: ./execute.t.sol#L505
[test_whenExecutionAfterExpiry_reverts]: ./execute.t.sol#L527
[test_givenTimelockIsDisabled_reverts]: ./execute.t.sol#L293
[test_givenDepositManagerIsDisabled_reverts]: ./execute.t.sol#L282
[test_givenTimelockPolicyIsInactive_reverts]: ./execute.t.sol#L304
[test_givenDepositManagerPolicyIsInactive_reverts]: ./execute.t.sol#L320
[test_givenPoliciesAreReactivated_executes]: ./execute.t.sol#L336
[test_givenConfigOperatorChanged_executionReverts]: ./execute.t.sol#L356
[test_givenConfigOperatorChangedAwayAndBack_executionSucceeds]: ./execute.t.sol#L372
[test_givenTimelockIsReEnabled_queuesAndExecutes]: ./execute.t.sol#L413
[test_whenExecuted_emitsExactEventsAndReleasesState]: ./execute.t.sol#L575
[test_whenCapUnchanged_executesAndReleasesKey]: ./execute.t.sol#L562
[test_givenBatchWithRouteCreation_whenMatured_permissionlessExecutionIsAtomic]: ./execute.t.sol#L162
[test_givenQueuedRoute_whenOperatorRoleRevoked_revertsAsStale]: ./execute.t.sol#L99
[test_givenQueuedRoute_whenOperatorRoleRevokedAndRegranted_succeeds]: ./execute.t.sol#L120
[test_givenQueuedRoute_whenAdminCreatesDirectly_revertsAsStale]: ./execute.t.sol#L137
[test_whenTargetSetterReverts_revertsAtomically]: ./execute.t.sol#L543
[test_givenBatchWithRouteCreation_whenLaterActionIsStale_rollsBackCreation]: ./execute.t.sol#L193
[test_givenForeignKernelAndPausedManager_whenExecuted_reverts]: ./execute.t.sol#L24
[test_givenManagerStatusGetterReverts_whenExecuted_reverts]: ./execute.t.sol#L47
[test_givenManagerStatusMalformed_whenExecuted_reverts]: ./execute.t.sol#L66

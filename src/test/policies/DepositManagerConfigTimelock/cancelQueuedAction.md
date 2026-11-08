# DepositManagerConfigTimelock.cancelQueuedAction coverage plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity and EMERGENCY authorization; local disablement remains allowed. Cancellation does not probe target readiness or operator selection.

Source: [DepositManagerConfigTimelock](../../../policies/deposits/DepositManagerConfigTimelock.sol), [queue](../../../policies/utils/TimelockBatchQueue.sol) and [configuration guards](../../../policies/utils/ConfigTimelockBatchQueue.sol). Scope: `DMCT-CANCEL`.

Only EMERGENCY_ROLE holders may cancel; ADMIN alone is insufficient. Accessibility checks
(existence, executed, cancelled) precede own Kernel activity and EMERGENCY authorization.
The timelock must remain Kernel-active; local disablement is permitted. There are no timing,
target-readiness, pre-state or config-operator gates. Cancellation remains available for an
unready, stale or expired pending action while the queue is active. It retains audit metadata
but deletes every sub-action and releases every destination-scoped guard/key.

Unchanged includes action IDs, payloads, destination-scoped key owners, target configuration,
receipt-token registration, custody and accounting. Reverts commit no logs. Queueing and
cancellation transfer no tokens; execution dispatches only the accepted configuration calls.

## Authorization and precedence

| ID | Caller | Action | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-CANCEL-A01 | Fuzz EMERGENCY-only and ADMIN+EMERGENCY holders | Pending cap | Cancel; exact event and full terminal cleanup | Covered: [test][test_givenEmergencyOnly_whenCancelled], [test][test_givenAdminAndEmergency_whenCancelled] |
| DMCT-CANCEL-A02 | Fuzz all callers without EMERGENCY; includes ADMIN and manager | Pending cap | ROLES_RequireRole(EMERGENCY_ROLE) | Covered: [test][test_givenCallerIsNotEmergency_reverts] |
| DMCT-CANCEL-A03 | Former EMERGENCY holder | Role revoked after queue | ROLES_RequireRole(EMERGENCY_ROLE); retain pending queue/key | Covered: [test][test_givenEmergencyRoleRevoked_whenCancelled_reverts] |
| DMCT-CANCEL-I01 | Fuzz all callers | Fuzz unknown uint64 IDs; seeds 0,MAX64 | ActionNotFound(id) before authorization | Covered: [test][test_whenUnknownActionCancelled_reverts], [test][test_whenUnknownActionBoundaryIds_reverts] |
| DMCT-CANCEL-I02 | EMERGENCY | Already executed | ActionAlreadyExecuted(id) | Covered: [test][test_givenActionAlreadyExecuted_reverts] |
| DMCT-CANCEL-I03 | EMERGENCY | Already cancelled | ActionCancelled(id) | Covered: [test][test_givenActionAlreadyCancelled_reverts] |

## Recovery availability

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-CANCEL-L01 | EMERGENCY | true | false | true | true | Cancel despite local pause | Covered: [test][test_givenQueuedAction_emergencyCancelsWhileDisabled] |
| DMCT-CANCEL-L02 | EMERGENCY | false | false | false | false | DepositManagerConfigTimelock_PolicyInactive(TL); queue, custody and lifecycle unchanged | Covered: [test][test_givenBothPoliciesPausedInactive_whenCancelled_reverts] |
| DMCT-CANCEL-L03 | EMERGENCY | false | true | false | true | DepositManagerConfigTimelock_PolicyInactive(TL); queue, custody and lifecycle unchanged | Covered: [test][test_givenPoliciesAreInactive_whenEmergencyCancels_reverts] |

## Timing, stale state and effects

| ID | Caller | Time / configuration | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| DMCT-CANCEL-N01 | EMERGENCY | Fuzz Q..MAX256, including before T and after E | Cancellation has no delay/expiry restriction | Covered: [test][test_givenActionIsExpired_cancelsAndReleasesConfigurationKey], [test][test_whenCancellationTimeVaries] |
| DMCT-CANCEL-D01 | EMERGENCY | Operator rotated and current minimum differs from queued pre-state | Cancel without validating dependency authority or state; preserve changed target | Covered: [test][test_givenOperatorRotatedAndStale_whenCancelled] |
| DMCT-CANCEL-P01 | Fuzz EMERGENCY holders | Pending singleton | Exactly one TimelockActionCancelled(id,caller); next ID and audit metadata preserved; queue/key fully cleared | Covered: [test][test_givenEmergencyOnly_whenCancelled] |
| DMCT-CANCEL-P02 | EMERGENCY | Pending singleton then same-key requeue | Released key admits a new monotonically increasing ID | Covered: [test][test_givenEmergency_cancelsAndReleasesConfigurationKey] |
| DMCT-CANCEL-P03 | EMERGENCY | Pending cap+period batch | Release every key so both settings can be independently queued again | Covered: [test][test_givenEmergency_cancelsBatchAndReleasesEveryConfigurationKey] |
| DMCT-CANCEL-P04 | EMERGENCY | Pending route creation | No route or receipt token created | Covered: [test][test_givenQueuedRoute_whenEmergencyCancels_routeIsNotCreated] |

- [x] Derive admission, input, timing and state-transition scenarios from the full call path.
- [x] Validate reciprocal mappings and focused execution.

[test_givenEmergencyOnly_whenCancelled]: ./cancel.t.sol#L209
[test_givenAdminAndEmergency_whenCancelled]: ./cancel.t.sol#L216
[test_givenCallerIsNotEmergency_reverts]: ./cancel.t.sol#L41
[test_givenEmergencyRoleRevoked_whenCancelled_reverts]: ./cancel.t.sol#L294
[test_whenUnknownActionCancelled_reverts]: ./cancel.t.sol#L223
[test_whenUnknownActionBoundaryIds_reverts]: ./cancel.t.sol#L235
[test_givenActionAlreadyExecuted_reverts]: ./cancel.t.sol#L124
[test_givenActionAlreadyCancelled_reverts]: ./cancel.t.sol#L140
[test_givenQueuedAction_emergencyCancelsWhileDisabled]: ./cancel.t.sol#L171
[test_givenBothPoliciesPausedInactive_whenCancelled_reverts]: ./cancel.t.sol#L253
[test_givenPoliciesAreInactive_whenEmergencyCancels_reverts]: ./cancel.t.sol#L67
[test_givenActionIsExpired_cancelsAndReleasesConfigurationKey]: ./cancel.t.sol#L156
[test_whenCancellationTimeVaries]: ./cancel.t.sol#L285
[test_givenOperatorRotatedAndStale_whenCancelled]: ./cancel.t.sol#L271
[test_givenEmergency_cancelsAndReleasesConfigurationKey]: ./cancel.t.sol#L52
[test_givenEmergency_cancelsBatchAndReleasesEveryConfigurationKey]: ./cancel.t.sol#L87
[test_givenQueuedRoute_whenEmergencyCancels_routeIsNotCreated]: ./cancel.t.sol#L22

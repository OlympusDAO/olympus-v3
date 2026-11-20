# BurnerLoansConfigTimelock.cancelQueuedAction coverage plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity, then the recorded proposer or a current EMERGENCY holder; local pause is permitted. Cancellation does not probe target readiness or operator selection.

Source: [cancelQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L167). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLCT-CANCEL` identifies this contract/function.

Own-policy admission: after the shared action-existence and terminal-state checks, require Kernel-active BurnerLoansConfigTimelock, then the recorded proposer or a current EMERGENCY holder. Own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)`. Local enablement and target state do not gate cancellation.

A proposer retains cancellation authority over its own batch after role revocation. The queue must
be Kernel-active and may be locally paused. Cancellation takes a `uint64` action ID and is allowed
before readiness, during the execution window and after expiry.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

The action exists and is pending; execution additionally lies inside the inclusive execution window. Those metadata/time checks precede the concrete lifecycle hook. Config.configOperator=BLCT for the execution success rows.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Config active: true; Config enabled: true.

| ID | Caller | Execution | Test |
| --- | --- | --- | --- |
| BLCT-CANCEL-A01 | EMERGENCY_ROLE holder | Cancel body | Covered: [test_givenReadyAction_whenCancel_thenComplete][test_givenReadyAction_whenCancel_thenComplete], [test_givenExistingEmergency_whenReadyActionCancelled_thenComplete][test_givenExistingEmergency_whenReadyActionCancelled_thenComplete] |
| BLCT-CANCEL-A02 | Recorded proposer | Cancel a multi-key batch one second before ready, at readiness, at expiry and one second after expiry | Covered: [test][test_givenPending_whenProposerCancelsAtTimeBoundaries] |
| BLCT-CANCEL-A03 | Another proposer without EMERGENCY | `NotAuthorised()`, including after expiry; queue and accounting unchanged | Covered: [test][test_givenExpiredBatch_whenAnotherProposerCancels_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-CANCEL-L01 | EMERGENCY_ROLE holder | true | true | true | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L02 | EMERGENCY_ROLE holder | true | true | false | true | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared] |
| BLCT-CANCEL-L03 | EMERGENCY_ROLE holder | true | true | false | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L04 | EMERGENCY_ROLE holder | true | false | true | true | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_thenCleared] |
| BLCT-CANCEL-L05 | EMERGENCY_ROLE holder | true | false | true | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L06 | EMERGENCY_ROLE holder | true | false | false | true | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared] |
| BLCT-CANCEL-L07 | EMERGENCY_ROLE holder | true | false | false | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L08 | EMERGENCY_ROLE holder | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L09 | EMERGENCY_ROLE holder | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L10 | EMERGENCY_ROLE holder | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L11 | EMERGENCY_ROLE holder | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L12 | EMERGENCY_ROLE holder | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L13 | EMERGENCY_ROLE holder | false | false | true | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L14 | EMERGENCY_ROLE holder | false | false | false | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L15 | EMERGENCY_ROLE holder | false | false | false | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts] |

A caller other than the recorded proposer must hold `EMERGENCY_ROLE` or the call reverts with
`NotAuthorised()`. Config rotation, pause and deactivation do not block cancellation.

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-CANCEL-I01 | EMERGENCY_ROLE holder | actionId=0; no action | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test_givenMissingZeroId_whenCancel_reverts][test_givenMissingZeroId_whenCancel_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-CANCEL-N01 | EMERGENCY_ROLE holder | Nonexistent actionId fuzz 1..MAX64 | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test_givenMissingNonzeroId_whenCancel_reverts][test_givenMissingNonzeroId_whenCancel_reverts] |

## Queue conflicts and execution

| ID | Caller | Queue / execution condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-CANCEL-P01 | EMERGENCY_ROLE holder | Already cancelled action | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; no committed logs | Covered: [test_givenAlreadyCancelled_whenCancelled_reverts][test_givenAlreadyCancelled_whenCancelled_reverts] |
| BLCT-CANCEL-P02 | EMERGENCY_ROLE holder | Pending expired action; now>expiresAt | Success | Expiry does not release keys by itself; cancellation does | Covered: [test_givenPendingExpired_whenCancelled_thenAllKeysReleased][test_givenPendingExpired_whenCancelled_thenAllKeysReleased] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-CANCEL-P03 | EMERGENCY_ROLE holder | Already executed action | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; no committed logs | Covered: [test_givenAlreadyExecuted_whenCancelled_reverts][test_givenAlreadyExecuted_whenCancelled_reverts] |
| BLCT-CANCEL-P04 | EMERGENCY_ROLE holder | Pending action; now<executableAt | Success | Cancel marker/event; payload and guards deleted; all keys released | Covered: [test_givenPendingBeforeReady_whenCancelled_thenAllKeysReleased][test_givenPendingBeforeReady_whenCancelled_thenAllKeysReleased] |
| BLCT-CANCEL-P05 | EMERGENCY_ROLE holder | Pending action; executableAt<=now<=expiresAt | Success | Cancel marker/event; all keys released | Covered: [test_givenPendingWithinWindow_whenCancelled_thenAllKeysReleased][test_givenPendingWithinWindow_whenCancelled_thenAllKeysReleased] |

## Shared assertions

Ensure same key can queue anew after cancellation, including expired actions; second cancel rejects. Multiple keys/scoped destinations and unrelated action keys isolated.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Cancellation lifecycle

EMERGENCY cancellation requires this timelock Kernel-active, regardless of local enablement. Target activity, enablement, Kernel/status metadata and operator selection are not read. The notice period and expiry do not block cancellation of a still-pending action. Successful cancellation clears all payloads, commitments and reservations without target calls or custody/accounting changes; own Policy inactivity still rejects before role checks.

[test_givenReadyAction_whenCancel_thenComplete]: ./cancelQueuedAction.t.sol#L292
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L16
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L29
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L42
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L55
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L68
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L81
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L94
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L107
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L127
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L147
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L167
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L187
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L207
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L227
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L247
[test_givenMissingZeroId_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L267
[test_givenMissingNonzeroId_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L279
[test_givenAlreadyCancelled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L301
[test_givenPendingExpired_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L334
[test_givenAlreadyExecuted_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L317
[test_givenPendingBeforeReady_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L350
[test_givenPendingWithinWindow_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L367

[test_givenExistingEmergency_whenReadyActionCancelled_thenComplete]: cancelQueuedAction.t.sol#L392
[test_givenPending_whenProposerCancelsAtTimeBoundaries]: ./cancelQueuedAction.t.sol#L397
[test_givenExpiredBatch_whenAnotherProposerCancels_reverts]: ./cancelQueuedAction.t.sol#L426

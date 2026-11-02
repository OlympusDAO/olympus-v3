# BurnerLoansConfigTimelock.cancelQueuedAction coverage plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity, then local enablement and EMERGENCY authorization. Cancellation does not probe target readiness or operator selection.

Source: [cancelQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L165). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope: `BLCT-CANCEL` identifies this contract/function.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

EMERGENCY role only, BLCT enabled+active; ADMIN/proposer/BL admin alone not permitted. Config active/enabled/operator selection irrelevant. actionId:uint64; cancellation permitted before ready, during window and after expiry.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

The action exists and is pending; execution additionally lies inside the inclusive execution window. Those metadata/time checks precede the concrete lifecycle hook. Config.configOperator=BLCT for the execution success rows.

## Authorization

Fixed for this table: Local active: true; Local enabled: true; Config active: true; Config enabled: true.

| ID | Caller | Execution | Test |
| --- | --- | --- | --- |
| BLCT-CANCEL-A01 | EMERGENCY_ROLE holder | Cancel body | Covered: [test_givenReadyAction_whenCancel_thenComplete][test_givenReadyAction_whenCancel_thenComplete] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Config active | Config enabled | Execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-CANCEL-L01 | EMERGENCY_ROLE holder | true | true | true | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L02 | EMERGENCY_ROLE holder | true | true | false | true | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared] |
| BLCT-CANCEL-L03 | EMERGENCY_ROLE holder | true | true | false | false | Cancel body | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared][test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared] |
| BLCT-CANCEL-L04 | EMERGENCY_ROLE holder | true | false | true | true | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L05 | EMERGENCY_ROLE holder | true | false | true | false | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L06 | EMERGENCY_ROLE holder | true | false | false | true | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L07 | EMERGENCY_ROLE holder | true | false | false | false | NotEnabled() | Covered: [test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L08 | EMERGENCY_ROLE holder | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Partial: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]; test implemented; production error differs from the required lifecycle/operator error |
| BLCT-CANCEL-L09 | EMERGENCY_ROLE holder | false | true | true | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Partial: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]; test implemented; production error differs from the required lifecycle/operator error |
| BLCT-CANCEL-L10 | EMERGENCY_ROLE holder | false | true | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Partial: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]; test implemented; production error differs from the required lifecycle/operator error |
| BLCT-CANCEL-L11 | EMERGENCY_ROLE holder | false | true | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Partial: [test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]; test implemented; production error differs from the required lifecycle/operator error |
| BLCT-CANCEL-L12 | EMERGENCY_ROLE holder | false | false | true | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L13 | EMERGENCY_ROLE holder | false | false | true | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts] |
| BLCT-CANCEL-L14 | EMERGENCY_ROLE holder | false | false | false | true | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts] |
| BLCT-CANCEL-L15 | EMERGENCY_ROLE holder | false | false | false | false | BurnerLoans_PolicyNotActive(TL) | Covered: [test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts][test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts] |

With BLCT active/enabled, fuzz all callers excluding EMERGENCY_ROLE holders: `ROLES_RequireRole(EMERGENCY_ROLE)`. ADMIN and original proposer without EMERGENCY are unauthorized. Config rotation/disable/deactivation does not block emergency cancellation; no selected-operator gate exists.

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

[test_givenReadyAction_whenCancel_thenComplete]: ./cancelQueuedAction.t.sol#L291
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L15
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L28
[test_givenTimelockActiveTrue_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_thenCleared]: ./cancelQueuedAction.t.sol#L41
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L54
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L67
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L80
[test_givenTimelockActiveTrue_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L93
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L106
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L126
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L146
[test_givenTimelockActiveFalse_givenTimelockEnabledTrue_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L166
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L186
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveTrue_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L206
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledTrue_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L226
[test_givenTimelockActiveFalse_givenTimelockEnabledFalse_givenConfigActiveFalse_givenConfigEnabledFalse_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L246
[test_givenMissingZeroId_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L266
[test_givenMissingNonzeroId_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L278
[test_givenAlreadyCancelled_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L300
[test_givenPendingExpired_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L333
[test_givenAlreadyExecuted_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L316
[test_givenPendingBeforeReady_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L349
[test_givenPendingWithinWindow_whenCancelled_thenAllKeysReleased]: ./cancelQueuedAction.t.sol#L366

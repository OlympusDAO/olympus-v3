# cancelQueuedAction scenario plan

Scope: inherited RDT cancellation with concrete Emergency-only authorization and conflict-key cleanup.

Co-located queue getters: after success, getQueuedAction retains proposer/timestamps and reports cancelled; nextActionId is unchanged; every pendingActionId key is zero and configuration-state count/destination default to zero. getQueuedActionLength/getQueuedSubAction reject the terminal action with its exact ITimelockBatchQueue status error; getQueuedConfigState gives ConfigStateIndexOutOfBounds for cleared slots. On rejection, all metadata, flags, payloads, destinations and key ownership match their pre-call values. Fuzz getter callers, including when RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Only Emergency; Admin or Revenue Distributor Admin alone cannot cancel. RDT must be locally enabled and Kernel-active. Operator selection is not a cancellation gate. Ready and expired actions can be cancelled; accessible-state checks precede caller authorization.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: mark cancelled, clear stored sub-actions, release all keys and emit TimelockActionCancelled(id,caller); preserve all RD configuration, custody and debts. Afterwards requeue the same keys when current queue gates permit.

## Authorization

| ID | Caller | Action status | RDT Kernel | RDT local | Operator binding | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-A01 | Unauthorized caller, fuzz; seed Admin, Revenue Distributor Admin, operator and proposer | Live queued action | Active | Enabled | Fuzz selected/rotated | ROLES_RequireRole(EMERGENCY_ROLE) | Unchanged | Covered: [fuzz and rotated operator][testFuzz_whenNonEmergencyCancels_reverts], [known identities][test_whenKnownNonEmergencyRolesCancel_reverts] |

## Behavior

| ID | Caller | Action shape | Timing state | RDT Kernel | RDT local | Operator binding | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-P01 | Emergency | Fuzz single/batch | Fuzz before-ready/ready/expired | Active | Enabled | Fuzz selected/rotated | Success | Release keys; getters expose cancelled metadata; replacement allowed | Covered: [both rescue selectors and timing][test_givenTimelockEnabledAndActive_whenEmergencyCancelsRescue], [batch and rotation][testFuzz_whenEmergencyCancelsBatch_releasesEveryKey], [replacement][test_whenCancelled_releasesKeyForReplacement] |
| CAN-L01 | Emergency | Fuzz pending/surplus rescue | Any live timing | Fuzz active/inactive | Disabled | Any | NotEnabled() | Action/guard/key and funds retained | Covered: [action, guard, key and custody retention][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts] |
| CAN-L02 | Emergency | Fuzz pending/surplus rescue | Any live timing | Inactive | Enabled | Any | RevenueDistributorConfigTimelock_PolicyInactive(RDT) | Action/guard/key and funds retained | Covered: [action, guard, key and custody retention][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts] |

## Invalid inputs

| ID | Caller | Action ID | Action status | RDT state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-I01 | Emergency; unauthorized caller separately | Fuzz unknown, seed 0/MAX64 | Missing | Fuzz lifecycle | ITimelockBatchQueue_ActionNotFound(id) | Unchanged; existence check precedes authority | Covered: [evidence][testFuzz_whenActionDoesNotExist_revertsBeforeLifecycle] |
| CAN-I02 | Emergency; unauthorized caller separately | Existing | Executed | Fuzz lifecycle | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; terminal check precedes authority | Covered: [evidence][testFuzz_whenActionAlreadyExecuted_revertsBeforeAuthority] |
| CAN-I03 | Emergency; unauthorized caller separately | Existing | Cancelled | Fuzz lifecycle | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; terminal check precedes authority | Covered: [evidence][testFuzz_whenActionAlreadyCancelled_revertsBeforeAuthority] |

## Read access

| ID | Caller | Action state | Unknown ID | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| CAN-V01 | Any getter caller, fuzz | Existing cancelled action | 0 or MAX64 | Existing getter exposes cancelled terminal state; unknown ID gives ITimelockBatchQueue_ActionNotFound(id); length getter gives ActionCancelled(id) | Unknown config-state count/destination and pendingActionId defaults are zero; reads never mutate state | Covered: [evidence][testFuzz_whenCancelledOrUnknownActionRead_returnsTerminalStateAndDefaults] |

[testFuzz_whenNonEmergencyCancels_reverts]: ./cancelQueuedAction.t.sol#L23
[test_whenKnownNonEmergencyRolesCancel_reverts]: ./cancelQueuedAction.t.sol#L45
[testFuzz_whenEmergencyCancelsBatch_releasesEveryKey]: ./cancelQueuedAction.t.sol#L279
[test_whenCancelled_releasesKeyForReplacement]: ./cancelQueuedAction.t.sol#L121
[testFuzz_whenActionDoesNotExist_revertsBeforeLifecycle]: ./cancelQueuedAction.t.sol#L71
[testFuzz_whenActionAlreadyExecuted_revertsBeforeAuthority]: ./cancelQueuedAction.t.sol#L89
[testFuzz_whenActionAlreadyCancelled_revertsBeforeAuthority]: ./cancelQueuedAction.t.sol#L105
[testFuzz_whenCancelledOrUnknownActionRead_returnsTerminalStateAndDefaults]: ./cancelQueuedAction.t.sol#L134

[test_givenTimelockEnabledAndActive_whenEmergencyCancelsRescue]: ./cancelQueuedAction.t.sol#L239
[test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts]: ./cancelQueuedAction.t.sol#L180

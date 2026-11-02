# cancelQueuedAction scenario plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity, then local enablement and EMERGENCY authorization. Cancellation does not probe target readiness or operator selection.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: inherited RDT cancellation with concrete Emergency-only authorization and conflict-key cleanup.

Co-located queue getters: after success, getQueuedAction retains proposer/timestamps and reports cancelled; nextActionId is unchanged; every pendingActionId key is zero and configuration-state count/destination default to zero. getQueuedActionLength/getQueuedSubAction reject the terminal action with its exact ITimelockBatchQueue status error; getQueuedConfigState gives ConfigStateIndexOutOfBounds for cleared slots. On rejection, all metadata, flags, payloads, destinations and key ownership match their pre-call values. Fuzz getter callers, including when RDT disabled/inactive or no longer selected.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Only Emergency; Admin or Revenue Distributor Admin alone cannot cancel. RDT must be locally enabled and Kernel-active. Operator selection is not a cancellation gate. Ready and expired actions can be cancelled; accessible-state checks precede caller authorization.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Success: mark cancelled, clear stored sub-actions, release all keys and emit TimelockActionCancelled(id,caller); preserve all RD configuration, custody and debts. Afterwards requeue the same keys when current queue gates permit.

## Authorization

| ID | Caller | Local active | Local enabled | Action status | Operator binding | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-A01 | Unauthorized caller, fuzz; seed Admin, Revenue Distributor Admin, operator and proposer | true | true | Live queued action | Fuzz selected/rotated | ROLES_RequireRole(EMERGENCY_ROLE) | Unchanged | Covered: [fuzz and rotated operator][test_whenNonEmergencyCancels_reverts], [known identities][test_whenKnownNonEmergencyRolesCancel_reverts] |

## Behavior

| ID | Caller | Local active | Local enabled | Action shape | Timing state | Operator binding | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-P01 | Emergency | true | true | Fuzz single/batch | Fuzz before-ready/ready/expired | Fuzz selected/rotated | Success | Release keys; getters expose cancelled metadata; replacement allowed | Covered: [both rescue selectors and timing][test_givenTimelockEnabledAndActive_whenEmergencyCancelsRescue], [batch and rotation][test_whenEmergencyCancelsBatch_releasesEveryKey], [replacement][test_whenCancelled_releasesKeyForReplacement] |
| CAN-L01 | Emergency | true | false | Fuzz pending/surplus rescue | Any live timing | Any | NotEnabled() | Action/guard/key and funds retained | Covered: [retained custody][test_givenActiveDisabledTimelock_whenEmergencyCancelsRescue_reverts], [seed][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts], [test][test_givenActiveDisabledTimelock_whenEmergencyCancelsDuringLiveWindow_reverts] |
| CAN-L03 | Emergency | false | false | Fuzz pending/surplus rescue | Any live timing | Any | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | Action/guard/key and funds retained | Covered: [retained custody][test_givenInactiveTimelock_whenEmergencyCancelsRescue_reverts], [seed][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts], [test][test_givenInactiveDisabledTimelock_whenEmergencyCancelsDuringLiveWindow_reverts] |
| CAN-L02 | Emergency | false | true | Fuzz pending/surplus rescue | Any live timing | Any | RevenueDistributorConfigTimelock_PolicyNotActive(RDT) | Action/guard/key and funds retained | Covered: [fuzz inactive local state][test_givenInactiveTimelock_whenEmergencyCancelsRescue_reverts], [action, guard, key and custody retention][test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts] |

## Invalid inputs

| ID | Caller | Action ID | Action status | RDT state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CAN-I01 | Emergency; unauthorized caller separately | Fuzz unknown, seed 0/MAX64 | Missing | Fuzz lifecycle | ITimelockBatchQueue_ActionNotFound(id) | Unchanged; existence check precedes authority | Covered: [evidence][test_whenActionDoesNotExist_revertsBeforeLifecycle] |
| CAN-I02 | Emergency; unauthorized caller separately | Existing | Executed | Fuzz lifecycle | ITimelockBatchQueue_ActionAlreadyExecuted(id) | Unchanged; terminal check precedes authority | Covered: [evidence][test_whenActionAlreadyExecuted_revertsBeforeAuthority] |
| CAN-I03 | Emergency; unauthorized caller separately | Existing | Cancelled | Fuzz lifecycle | ITimelockBatchQueue_ActionCancelled(id) | Unchanged; terminal check precedes authority | Covered: [evidence][test_whenActionAlreadyCancelled_revertsBeforeAuthority] |

## Read access

| ID | Caller | Action state | Unknown ID | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| CAN-V01 | Any getter caller, fuzz | Existing cancelled action | 0 or MAX64 | Existing getter exposes cancelled terminal state; unknown ID gives ITimelockBatchQueue_ActionNotFound(id); length getter gives ActionCancelled(id) | Unknown config-state count/destination and pendingActionId defaults are zero; reads never mutate state | Covered: [evidence][test_whenCancelledOrUnknownActionRead_returnsTerminalStateAndDefaults] |

[test_whenNonEmergencyCancels_reverts]: ./cancelQueuedAction.t.sol#L24
[test_whenKnownNonEmergencyRolesCancel_reverts]: ./cancelQueuedAction.t.sol#L43
[test_whenEmergencyCancelsBatch_releasesEveryKey]: ./cancelQueuedAction.t.sol#L299
[test_whenCancelled_releasesKeyForReplacement]: ./cancelQueuedAction.t.sol#L118
[test_whenActionDoesNotExist_revertsBeforeLifecycle]: ./cancelQueuedAction.t.sol#L69
[test_whenActionAlreadyExecuted_revertsBeforeAuthority]: ./cancelQueuedAction.t.sol#L86
[test_whenActionAlreadyCancelled_revertsBeforeAuthority]: ./cancelQueuedAction.t.sol#L102
[test_whenCancelledOrUnknownActionRead_returnsTerminalStateAndDefaults]: ./cancelQueuedAction.t.sol#L131
[test_givenTimelockEnabledAndActive_whenEmergencyCancelsRescue]: ./cancelQueuedAction.t.sol#L259
[test_givenTimelockUnavailable_whenEmergencyCancelsRescue_reverts]: ./cancelQueuedAction.t.sol#L177
[test_givenActiveDisabledTimelock_whenEmergencyCancelsDuringLiveWindow_reverts]: ./cancelQueuedAction.t.sol#L385
[test_givenInactiveDisabledTimelock_whenEmergencyCancelsDuringLiveWindow_reverts]: ./cancelQueuedAction.t.sol#L417
[test_givenActiveDisabledTimelock_whenEmergencyCancelsRescue_reverts]: ./cancelQueuedAction.t.sol#L230
[test_givenInactiveTimelock_whenEmergencyCancelsRescue_reverts]: ./cancelQueuedAction.t.sol#L194

# BurnerLoansInventoryConfigTimelock.cancelQueuedAction coverage plan

Shared action existence and terminal-status checks precede the concrete hook. The hook requires own Kernel activity, then local enablement and EMERGENCY authorization. Cancellation does not probe target readiness or operator selection.

Source: [cancelQueuedAction](../../../policies/utils/TimelockBatchQueue.sol#L165). Concrete behavior: [_validateCancellation](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L248).

## Scope and fixtures

`MAXn` denotes `2**n-1`; time is measured in seconds.

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

Errors use the exact declarations in [queue errors](../../../policies/interfaces/utils/ITimelockBatchQueue.sol), [configuration queue errors](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol), [Inventory timelock errors](../../../policies/interfaces/burnerloans/IBurnerLoansInventoryConfigTimelock.sol), and [shared Burner Loans errors](../../../policies/interfaces/burnerloans/IBurnerLoansErrors.sol). `Action*` errors below carry the `ITimelockBatchQueue_` prefix; `Config*` errors carry `IConfigTimelockBatchQueue_`; `InvalidInventory` and `SubActionCallFailed` carry `BurnerLoansInventoryTimelock_`.

## Authorization

Pending action; TL active/enabled; T=executableAt and E=expiresAt. Cancellation has one specific role requirement.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CANCEL-A01 | EMERGENCY_ROLE holder | Accepted role | Success | cancelled=true; payload/guards cleared; key released; exact event | Covered: [test][test_givenPendingAction_whenEmergencyCancels_thenExactCleanup]; [test][test_givenNoticePeriod_whenCancelled_thenExactCleanup]; [test][test_givenExpiredWindow_whenCancelled_thenExactCleanup]; [test][test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup] |
| BLINCT-CANCEL-A02 | Fuzz outside EMERGENCY_ROLE holders | Seed ADMIN-only and BL-admin-only | ROLES_RequireRole(EMERGENCY_ROLE) | Unchanged | Covered: [test][test_whenCallerLacksEmergency_reverts]; [test][test_givenOtherAdministrativeRoles_whenCancelled_reverts] |

## Lifecycle

Use EMERGENCY caller with cached ROLES.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-CANCEL-L01 | EMERGENCY | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenActiveDisabledTimelock_whenCancelled_reverts] |
| BLINCT-CANCEL-L02 | EMERGENCY | false | true | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveTimelock_whenCancelled_reverts] |
| BLINCT-CANCEL-L03 | EMERGENCY | false | false | BurnerLoans_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabledTimelock_whenCancelled_reverts] |

## Target independence

Inventory failure/controller drift must not prevent cancellation.

| ID | Caller | State | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CANCEL-D01 | EMERGENCY | I inactive | Success | No target readiness call; release old key | Covered: [test][test_givenInactiveInventory_whenCancelled_thenNoReadinessCalls] |
| BLINCT-CANCEL-D02 | EMERGENCY | I disabled | Success | No target readiness call; release old key | Covered: [test][test_givenPausedInventory_whenCancelled_thenNoReadinessCalls] |
| BLINCT-CANCEL-D03 | EMERGENCY | I reports another Kernel | Success | No target readiness call; release old key | Covered: [test][test_givenInventoryKernelMismatch_whenCancelled_thenNoReadinessCalls] |
| BLINCT-CANCEL-D04 | EMERGENCY | Controller replaced | Success | No controller check; release old key | Covered: [test][test_givenControllerReplaced_whenCancelled_thenNoReadinessCalls] |

## Invalid action IDs

Standard terminal-state checks precede lifecycle and authorization.

| ID | Caller | Action state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CANCEL-I01 | Fuzz all callers | Unknown id; seed 0,MAX64 | ActionNotFound(id) |Unchanged; getQueuedAction/length/subAction use ActionNotFound(id); absent config count/destination are 0; getQueuedConfigState(id,0,0) uses ConfigStateIndexOutOfBounds(id,0,0,0) | Covered: [test][test_whenActionUnknown_revertsBeforeAuthorization]; [test][test_whenUnknownIdAtTypeBounds_reverts] |
| BLINCT-CANCEL-I02 | Fuzz all callers | Executed id | ActionAlreadyExecuted(id) |Unchanged; metadata retains executed=true; length/subAction reject ActionAlreadyExecuted(id); payload/destination/state/key cleared | Covered: [test][test_givenExecutedAction_whenCalled_revertsBeforeAuthorization] |
| BLINCT-CANCEL-I03 | Fuzz all callers | Cancelled id | ActionCancelled(id) |Unchanged; metadata retains cancelled=true; length/subAction reject ActionCancelled(id); payload/destination/state/key cleared | Covered: [test][test_givenCancelledAction_whenCalled_revertsBeforeAuthorization] |

## Cancellation timing and cleanup

A pending action is cancellable without waiting for notice or meeting the execution window.

| ID | Caller | Time | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-CANCEL-N01 | EMERGENCY | Fuzz queuedAt..T-1; seed both ends | Success | cancelled=true; metadata retained; payload, destination, state records and key cleared; TimelockActionCancelled(id,caller) | Covered: [test][test_givenPendingAction_whenEmergencyCancels_thenExactCleanup]; [test][test_givenNoticePeriod_whenCancelled_thenExactCleanup]; [test][test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup] |
| BLINCT-CANCEL-N02 | EMERGENCY | now=E | Success | Same exact cleanup/event; no Inventory payout | Covered: [test][test_givenPendingAction_whenEmergencyCancels_thenExactCleanup]; [test][test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup] |
| BLINCT-CANCEL-N03 | EMERGENCY | Fuzz E+1..MAX48; seed E+1,MAX48 | Success | Same cleanup; expired action cannot strand key | Covered: [test][test_givenPendingAction_whenEmergencyCancels_thenExactCleanup]; [test][test_givenExpiredWindow_whenCancelled_thenExactCleanup]; [test][test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup] |
| BLINCT-CANCEL-P01 | EMERGENCY then ADMIN proposer | Cancel old action, queue another recovery | New ID accepted | Released key assigned to new ID; old metadata stays cancelled | Covered: [test][test_givenCancelledAction_whenRecoveryRequeued_thenFreshIdOwnsKey] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_givenPendingAction_whenEmergencyCancels_thenExactCleanup]: ./cancelQueuedAction.t.sol#L27
[test_givenNoticePeriod_whenCancelled_thenExactCleanup]: ./cancelQueuedAction.t.sol#L224
[test_givenExpiredWindow_whenCancelled_thenExactCleanup]: ./cancelQueuedAction.t.sol#L235
[test_givenCancellationTimeEndpointSeeds_whenCancelled_thenExactCleanup]: ./cancelQueuedAction.t.sol#L246
[test_whenCallerLacksEmergency_reverts]: ./cancelQueuedAction.t.sol#L55
[test_givenOtherAdministrativeRoles_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L283
[test_givenActiveDisabledTimelock_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L64
[test_givenInactiveTimelock_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L87
[test_givenInactiveInventory_whenCancelled_thenNoReadinessCalls]: ./cancelQueuedAction.t.sol#L125
[test_givenPausedInventory_whenCancelled_thenNoReadinessCalls]: ./cancelQueuedAction.t.sol#L135
[test_givenInventoryKernelMismatch_whenCancelled_thenNoReadinessCalls]: ./cancelQueuedAction.t.sol#L145
[test_givenControllerReplaced_whenCancelled_thenNoReadinessCalls]: ./cancelQueuedAction.t.sol#L155
[test_whenActionUnknown_revertsBeforeAuthorization]: ./cancelQueuedAction.t.sol#L165
[test_whenUnknownIdAtTypeBounds_reverts]: ./cancelQueuedAction.t.sol#L275
[test_givenExecutedAction_whenCalled_revertsBeforeAuthorization]: ./cancelQueuedAction.t.sol#L186
[test_givenCancelledAction_whenCalled_revertsBeforeAuthorization]: ./cancelQueuedAction.t.sol#L205
[test_givenCancelledAction_whenRecoveryRequeued_thenFreshIdOwnsKey]: ./cancelQueuedAction.t.sol#L100
[test_givenInactiveDisabledTimelock_whenCancelled_reverts]: ./cancelQueuedAction.t.sol#L71

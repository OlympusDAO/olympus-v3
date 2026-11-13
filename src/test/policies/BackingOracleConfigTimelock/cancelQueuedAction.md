# cancelQueuedAction scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol` and inherited framework hooks.

ADMIN = distinct _ADMIN actor; backing_admin = proposer; EMERGENCY = emergency.
Backing is reserve per OHM in 18 decimals; ordinary enabled backing is 100e18.
Reverts preserve authoritative backing, operator selection, action IDs, flags,
payloads and reservations. No token custody or transfers occur. Roles are independent
of Kernel membership and local enablement. Both policies use real Kernel/ROLES.

The default queue is active, enabled and selected on its immutable active oracle.
The oracle starts paused unless givenEnabled/recovery setup enables it. Constructor
cases have no queue lifecycle yet. Queue activation permits a paused oracle and
does not read its enabled flag. Runtime queue/execution require both policies
active/enabled and current selection. Cancellation reads no target metadata.

E=queuedAt+delay; X=E+7 days. Through X, inclusive, only ADMIN, EMERGENCY and the
action's proposer cancel; from X+1 any caller does. The proposer is matched by
address: it cancels after losing backing_admin, another backing_admin fails, and
backing_admin fails on an ADMIN proposal. Other callers get NotAuthorised.
Own activity is required first for every caller, expired actions included; own
pause is allowed, and target readiness/selection are never read. Cancellation
clears actions/commitments and releases keys. Unexpired time is fuzzed over
[0,8 days] and expired time over [8 days+1,MAX48−now]; EMERGENCY and inactive
cases fuzz notice/live/expired time; X, X+1 and absent IDs 0/1/MAX64 are
explicitly seeded.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-CANCELQUEUEDACTION-05 | ADMIN | true | true | independent | independent | when Absent Boundary Seeds reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsentBoundarySeeds_reverts] |
| BO-CANCELQUEUEDACTION-01 | EMERGENCY | true | Fuzz false/true | true | Fuzz false/true | when Emergency Cancels; explicit enabled queue/oracle seed | Success; payload/commitments cleared, key released; backing unchanged | Covered: [fuzz states][test_whenEmergencyCancels]; [enabled seed][test_givenOwnEnabled_whenEmergencyCancels] |
| BO-CANCELQUEUEDACTION-02 | Fuzz unauthorized | true | true | independent | independent | when Unauthorized reverts; fuzz notice/live time through X | NotAuthorised; intent/key retained | Covered: [test][test_whenUnauthorized_reverts] |
| BO-CANCELQUEUEDACTION-03 | EMERGENCY | false | Fuzz false/true | independent | independent | given Inactive when Cancel reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenCancel_reverts] |
| BO-CANCELQUEUEDACTION-04 | ADMIN | true | true | independent | independent | when Absent reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsent_reverts] |
| BO-REPLACEMENT-03 | EMERGENCY | true | false | independent | independent | given Own Paused when Cancel With Broken Target | Success; exact authoritative state/getter assertions | Covered: [test][test_givenOwnPaused_whenCancelWithBrokenTarget] |
| BO-CANCELQUEUEDACTION-06 | Unrelated | true | true | true | true | when Unauthorized At Expiry reverts | NotAuthorised at X, key retained; the same caller then executes at X | Covered: [test][test_whenUnauthorizedAtExpiry_reverts] |
| BO-CANCELQUEUEDACTION-07 | Second backing_admin | true | true | independent | independent | when Other Backing Admin reverts | NotAuthorised; intent retained | Covered: [test][test_whenOtherBackingAdmin_reverts] |
| BO-CANCELQUEUEDACTION-08 | backing_admin | true | true | independent | independent | given Admin Proposal when Backing Admin reverts | NotAuthorised; ADMIN remains proposer, intent retained | Covered: [test][test_givenAdminProposal_whenBackingAdmin_reverts] |
| BO-CANCELQUEUEDACTION-09 | backing_admin (proposer) | true | Fuzz false/true | independent | independent | when Proposer Cancels; fuzz notice/live time through X; notice, window and paused seeds | Success; payload/commitments cleared, key released; backing unchanged | Covered: [fuzz states][test_whenProposerCancels]; [notice seed][test_whenProposerCancelsDuringNotice]; [window seed][test_whenProposerCancelsInWindow]; [paused seed][test_givenOwnPaused_whenProposerCancels] |
| BO-CANCELQUEUEDACTION-10 | Proposer without backing_admin | true | true | independent | independent | given Proposer Lost Role when Proposer Cancels | Success; payload/commitments cleared, key released | Covered: [test][test_givenProposerLostRole_whenProposerCancels] |
| BO-CANCELQUEUEDACTION-11 | ADMIN | true | Fuzz false/true | independent | independent | when Admin Cancels a backing_admin proposal; fuzz notice/live time through X; enabled and paused seeds | Success; payload/commitments cleared, key released | Covered: [fuzz states][test_whenAdminCancels]; [enabled seed][test_givenOwnEnabled_whenAdminCancels]; [paused seed][test_givenOwnPaused_whenAdminCancels] |
| BO-CANCELQUEUEDACTION-12 | Fuzz any caller | true | Fuzz false/true | independent | independent | given Expired when Any Caller Cancels; fuzz time after X; paused unrelated seed at X+1 | Success; payload/commitments cleared, key released; backing unchanged | Covered: [fuzz states][test_givenExpired_whenAnyCallerCancels]; [paused seed][test_givenExpired_givenOwnPaused_whenUnrelatedCancels] |
| BO-CANCELQUEUEDACTION-13 | Unrelated | true | true | true | true | given Expired when Unrelated Cancels One Second After Expiry | Execution ITimelockBatchQueue_ActionExpired(id,X); cancellation at X+1 succeeds; fresh proposal queues | Covered: [test][test_givenExpired_whenUnrelatedCancelsOneSecondAfterExpiry] |
| BO-CANCELQUEUEDACTION-14 | Fuzz any caller | false | Fuzz false/true | independent | independent | given Inactive when Any Caller Cancels reverts; fuzz notice/live/expired time | BackingOracleTimelock_PolicyNotActive(self); intent/key retained | Covered: [test][test_givenInactive_whenAnyCallerCancels_reverts] |
| BO-CANCELQUEUEDACTION-15 | backing_admin (proposer); ADMIN; unrelated after X | false, then true | true | independent | independent | given Inactive when Proposer/Admin Cancels reverts; given Inactive given Expired when Unrelated Cancels reverts | BackingOracleTimelock_PolicyNotActive(self); success after reactivation | Covered: [proposer][test_givenInactive_whenProposerCancels_reverts]; [ADMIN][test_givenInactive_whenAdminCancels_reverts]; [expired][test_givenInactive_givenExpired_whenUnrelatedCancels_reverts] |
| BO-CANCELQUEUEDACTION-16 | Unrelated | false, then true | true | independent | independent | given Inactive when Unauthorized reverts | BackingOracleTimelock_PolicyNotActive(self) before authorization; NotAuthorised after reactivation | Covered: [test][test_givenInactive_whenUnauthorized_reverts] |
| BO-REPLACEMENT-04 | backing_admin (proposer) | true | false | independent | independent | given Own Paused when Proposer Cancels With Broken Target | Success with zero oracle calls | Covered: [test][test_givenOwnPaused_whenProposerCancelsWithBrokenTarget] |
| BO-REPLACEMENT-05 | Unrelated | true | false | independent | independent | given Own Paused given Expired when Unrelated Cancels With Broken Target | Success with zero oracle calls | Covered: [test][test_givenOwnPaused_givenExpired_whenUnrelatedCancelsWithBrokenTarget] |
| BO-CANCELQUEUEDACTION-17 | backing_admin (proposer) | true | true | true | true | given Backing Drift when Proposer Cancels And Requeues | Execution ConfigStateChanged(expected/current backing hash); conflicting proposal ConfigKeyPending; cancellation releases key; fresh proposal commits the drifted backing and executes | Covered: [test][test_givenBackingDrift_whenProposerCancelsAndRequeues] |

[test_whenAbsentBoundarySeeds_reverts]: ./cancelQueuedAction.t.sol#L64
[test_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L71
[test_whenUnauthorized_reverts]: ./cancelQueuedAction.t.sol#L113
[test_givenInactive_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L126
[test_whenAbsent_reverts]: ./cancelQueuedAction.t.sol#L143
[test_givenOwnPaused_whenCancelWithBrokenTarget]: ./cancelQueuedAction.t.sol#L148
[test_givenOwnEnabled_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L108
[test_whenUnauthorizedAtExpiry_reverts]: ./cancelQueuedAction.t.sol#L167
[test_whenOtherBackingAdmin_reverts]: ./cancelQueuedAction.t.sol#L182
[test_givenAdminProposal_whenBackingAdmin_reverts]: ./cancelQueuedAction.t.sol#L196
[test_whenProposerCancels]: ./cancelQueuedAction.t.sol#L208
[test_whenProposerCancelsDuringNotice]: ./cancelQueuedAction.t.sol#L226
[test_whenProposerCancelsInWindow]: ./cancelQueuedAction.t.sol#L231
[test_givenOwnPaused_whenProposerCancels]: ./cancelQueuedAction.t.sol#L236
[test_givenProposerLostRole_whenProposerCancels]: ./cancelQueuedAction.t.sol#L241
[test_whenAdminCancels]: ./cancelQueuedAction.t.sol#L249
[test_givenOwnEnabled_whenAdminCancels]: ./cancelQueuedAction.t.sol#L260
[test_givenOwnPaused_whenAdminCancels]: ./cancelQueuedAction.t.sol#L265
[test_givenExpired_whenAnyCallerCancels]: ./cancelQueuedAction.t.sol#L270
[test_givenExpired_givenOwnPaused_whenUnrelatedCancels]: ./cancelQueuedAction.t.sol#L284
[test_givenExpired_whenUnrelatedCancelsOneSecondAfterExpiry]: ./cancelQueuedAction.t.sol#L289
[test_givenInactive_whenAnyCallerCancels_reverts]: ./cancelQueuedAction.t.sol#L308
[test_givenInactive_whenProposerCancels_reverts]: ./cancelQueuedAction.t.sol#L326
[test_givenInactive_whenAdminCancels_reverts]: ./cancelQueuedAction.t.sol#L331
[test_givenInactive_givenExpired_whenUnrelatedCancels_reverts]: ./cancelQueuedAction.t.sol#L336
[test_givenInactive_whenUnauthorized_reverts]: ./cancelQueuedAction.t.sol#L341
[test_givenOwnPaused_whenProposerCancelsWithBrokenTarget]: ./cancelQueuedAction.t.sol#L356
[test_givenOwnPaused_givenExpired_whenUnrelatedCancelsWithBrokenTarget]: ./cancelQueuedAction.t.sol#L361
[test_givenBackingDrift_whenProposerCancelsAndRequeues]: ./cancelQueuedAction.t.sol#L369

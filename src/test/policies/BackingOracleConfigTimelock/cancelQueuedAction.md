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

EMERGENCY only; ADMIN/proposer alone fail. Own activity is required, own pause
is allowed, and target readiness/selection are never read. Cancellation clears
actions/commitments and releases keys. Notice/live/expired time is fuzzed over
uint48 elapsed seconds; absent IDs 0/1/MAX64 are explicitly seeded.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-CANCELQUEUEDACTION-05 | ADMIN | true | true | independent | independent | when Absent Boundary Seeds reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsentBoundarySeeds_reverts] |
| BO-CANCELQUEUEDACTION-01 | EMERGENCY | true | Fuzz false/true | true | Fuzz false/true | when Emergency Cancels; explicit enabled queue/oracle seed | Success; payload/commitments cleared, key released; backing unchanged | Covered: [fuzz states][test_whenEmergencyCancels]; [enabled seed][test_givenOwnEnabled_whenEmergencyCancels] |
| BO-CANCELQUEUEDACTION-02 | Fuzz unauthorized | true | true | independent | independent | when Unauthorized reverts | ROLES_RequireRole | Covered: [test][test_whenUnauthorized_reverts] |
| BO-CANCELQUEUEDACTION-03 | EMERGENCY | false | Fuzz false/true | independent | independent | given Inactive when Cancel reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenCancel_reverts] |
| BO-CANCELQUEUEDACTION-04 | ADMIN | true | true | independent | independent | when Absent reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsent_reverts] |
| BO-REPLACEMENT-03 | EMERGENCY | true | false | independent | independent | given Own Paused when Cancel With Broken Target | Success; exact authoritative state/getter assertions | Covered: [test][test_givenOwnPaused_whenCancelWithBrokenTarget] |

[test_whenAbsentBoundarySeeds_reverts]: ./cancelQueuedAction.t.sol#L23
[test_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L30
[test_whenUnauthorized_reverts]: ./cancelQueuedAction.t.sol#L72
[test_givenInactive_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L82
[test_whenAbsent_reverts]: ./cancelQueuedAction.t.sol#L99
[test_givenOwnPaused_whenCancelWithBrokenTarget]: ./cancelQueuedAction.t.sol#L104
[test_givenOwnEnabled_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L67

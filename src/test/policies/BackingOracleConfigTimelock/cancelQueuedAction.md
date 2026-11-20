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

The recorded proposer or a current EMERGENCY holder can cancel. The proposer retains this
authority after role revocation. The queue must be Kernel-active and may be locally paused.
Cancellation makes no target reads and clears
actions/commitments and releases keys. Notice/live/expired time is fuzzed over
uint48 elapsed seconds; absent IDs 0/1/MAX64 are explicitly seeded.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-CANCELQUEUEDACTION-05 | ADMIN | true | true | independent | independent | when Absent Boundary Seeds reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsentBoundarySeeds_reverts] |
| BO-CANCELQUEUEDACTION-01 | EMERGENCY | true | Fuzz false/true | true | Fuzz false/true | when Emergency Cancels; explicit enabled queue/oracle seed | Success; payload/commitments cleared, key released; backing unchanged | Covered: [fuzz states][test_whenEmergencyCancels]; [enabled seed][test_givenOwnEnabled_whenEmergencyCancels] |
| BO-CANCELQUEUEDACTION-02 | Fuzz outside recorded proposer and EMERGENCY | true | true | independent | independent | when Unauthorized reverts | `NotAuthorised()` | Covered: [test][test_whenUnauthorized_reverts] |
| BO-CANCELQUEUEDACTION-03 | Recorded proposer or EMERGENCY | false | Fuzz false/true | independent | independent | given Inactive when Cancel reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenInactive_whenCancel_reverts] |
| BO-CANCELQUEUEDACTION-04 | ADMIN | true | true | independent | independent | when Absent reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsent_reverts] |
| BO-CANCELQUEUEDACTION-06 | Recorded proposer, role revoked | true | false | independent | independent | Pending batch and oracle calls revert | Exact cancellation event and backing key released | Covered: [test][test_givenRevokedProposer_givenPaused_whenProposerCancels] |
| BO-REPLACEMENT-03 | EMERGENCY | true | false | independent | independent | given Own Paused when Cancel With Broken Target | Success; exact authoritative state/getter assertions | Covered: [test][test_givenOwnPaused_whenCancelWithBrokenTarget] |

[test_whenAbsentBoundarySeeds_reverts]: ./cancelQueuedAction.t.sol#L20
[test_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L27
[test_whenUnauthorized_reverts]: ./cancelQueuedAction.t.sol#L69
[test_givenInactive_whenCancel_reverts]: ./cancelQueuedAction.t.sol#L79
[test_whenAbsent_reverts]: ./cancelQueuedAction.t.sol#L125
[test_givenOwnPaused_whenCancelWithBrokenTarget]: ./cancelQueuedAction.t.sol#L130
[test_givenOwnEnabled_whenEmergencyCancels]: ./cancelQueuedAction.t.sol#L64
[test_givenRevokedProposer_givenPaused_whenProposerCancels]: ./cancelQueuedAction.t.sol#L101

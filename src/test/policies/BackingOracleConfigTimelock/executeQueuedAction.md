# executeQueuedAction scenarios

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

Existence/terminal/time checks precede policy readiness. E=queuedAt+delay;
X=E+7 days; execution is inclusive [E,X]. Executor and the full valid time interval
are fuzzed independently; exact notice/expiry success also impersonates an unrelated
address 0xB0B with no ADMIN, backing_admin or EMERGENCY role; E−1/E/X/X+1 and absent IDs 0/1/MAX64 are explicit seeds.
ADMIN backing drift causes ConfigStateChanged before dispatch. Failed dispatch
retains intent/key; successful retry requires original commitments and deadlines.
Replacement queues have independent reservations but only the selected queue has
write authority. No historical epoch is added: away-and-back state can match again.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-EXECUTEQUEUEDACTION-10 | Any caller (permissionless) | true | true | true | true | when Absent Boundary Seeds reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsentBoundarySeeds_reverts] |
| BO-EXECUTEQUEUEDACTION-01 | Fuzz any caller | true | true | true | true | when Permissionless Execution | Success; exact authoritative state/getter assertions | Covered: [test][test_whenPermissionlessExecution] |
| BO-EXECUTEQUEUEDACTION-02 | Any caller (permissionless) | true | true | true | true | when Exact Notice | Success; exact authoritative state/getter assertions | Covered: [test][test_whenExactNotice] |
| BO-EXECUTEQUEUEDACTION-03 | Any caller (permissionless) | true | true | true | true | when Exact Expiry | Success; exact authoritative state/getter assertions | Covered: [test][test_whenExactExpiry] |
| BO-EXECUTEQUEUEDACTION-04 | Any caller (permissionless) | true | true | true | true | when Before Notice reverts | ITimelockBatchQueue_ActionNotReady(id,E) | Covered: [test][test_whenBeforeNotice_reverts] |
| BO-EXECUTEQUEUEDACTION-05 | Any caller (permissionless) | true | true | true | true | when After Expiry reverts | ITimelockBatchQueue_ActionExpired(id,X); reservation retained | Covered: [test][test_whenAfterExpiry_reverts] |
| BO-EXECUTEQUEUEDACTION-06 | Any caller (permissionless) | true | true | true | true | given Backing Drift when Execute reverts | ConfigStateChanged(expected/current backing hash); original-state retry succeeds | Covered: [test][test_givenBackingDrift_whenExecute_reverts] |
| BO-EXECUTEQUEUEDACTION-07 | Any caller (permissionless) | true | false | true | false | given Disabled when Execute reverts | PolicyDependency_NotActive(oracle); intent retained | Covered: [test][test_givenDisabled_whenExecute_reverts] |
| BO-EXECUTEQUEUEDACTION-08 | Any caller (permissionless) | true | true | false | true | given Inactive when Execute reverts | PolicyDependency_NotActive(oracle); intent retained | Covered: [test][test_givenInactive_whenExecute_reverts] |
| BO-EXECUTEQUEUEDACTION-09 | Any caller (permissionless) | true | true | true | true | when Absent reverts | ITimelockBatchQueue_ActionNotFound(id) | Covered: [test][test_whenAbsent_reverts] |
| BO-TIMELOCK-EXECUTEQUEUEDACTION-03 | Any caller (permissionless) | true | false | true | true | given Own Paused when Execute reverts | NotEnabled | Covered: [test][test_givenOwnPaused_whenExecute_reverts] |
| BO-TIMELOCK-EXECUTEQUEUEDACTION-02 | Any caller (permissionless) | false | true | true | true | given Own Inactive when Execute reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenOwnInactive_whenExecute_reverts] |
| BO-TIMELOCK-EXECUTEQUEUEDACTION-01 | Any caller (permissionless) | true | true | true | true | given Target Failure when Execute reverts | Exact downstream error; flags/payload/key rolled back; retry succeeds | Covered: [test][test_givenTargetFailure_whenExecute_reverts] |
| BO-REPLACEMENT-01 | Any caller (permissionless) | true | true | true | true | given Replacement when Old Queue Executes reverts | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenReplacement_whenOldQueueExecutes_reverts] |
| BO-EXECUTEQUEUEDACTION-MODEL | Authorized handler | true | Varies | true | Varies | Direct updates, queue, execute, cancel and pause sequences in [90e18,110e18] | Independent model of backing/lifecycle/pending key/payload agrees | Covered: [model][invariant_backingAndLifecycleMatchModel] |

[test_whenAbsentBoundarySeeds_reverts]: ./executeQueuedAction.t.sol#L20
[test_whenPermissionlessExecution]: ./executeQueuedAction.t.sol#L27
[test_whenExactNotice]: ./executeQueuedAction.t.sol#L60
[test_whenExactExpiry]: ./executeQueuedAction.t.sol#L69
[test_whenBeforeNotice_reverts]: ./executeQueuedAction.t.sol#L78
[test_whenAfterExpiry_reverts]: ./executeQueuedAction.t.sol#L93
[test_givenBackingDrift_whenExecute_reverts]: ./executeQueuedAction.t.sol#L109
[test_givenDisabled_whenExecute_reverts]: ./executeQueuedAction.t.sol#L138
[test_givenInactive_whenExecute_reverts]: ./executeQueuedAction.t.sol#L152
[test_whenAbsent_reverts]: ./executeQueuedAction.t.sol#L164
[test_givenOwnPaused_whenExecute_reverts]: ./executeQueuedAction.t.sol#L169
[test_givenOwnInactive_whenExecute_reverts]: ./executeQueuedAction.t.sol#L183
[test_givenTargetFailure_whenExecute_reverts]: ./executeQueuedAction.t.sol#L195
[test_givenReplacement_whenOldQueueExecutes_reverts]: ./executeQueuedActionReplacement.t.sol#L13
[invariant_backingAndLifecycleMatchModel]: ./executeQueuedAction.invariant.t.sol#L32

# queueSetBacking scenarios

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

The normal proposer is the operational manager holding `backing_admin` (_PROPOSER),
with no ADMIN role. Numeric and lifecycle cases use this actor. Direct ADMIN
proposal authority and overlapping roles have separate authorization tests.
Proposer classes: backing_admin, ADMIN and overlapping roles. Unauthorized caller
fuzz excludes ADMIN and proposer. Valid values fuzz [90e18,110e18]; invalid values
fuzz [1,90e18−1] and [110e18+1,MAX256]. Zero/one/MAX256 and adjacent bounds are seeded.
The one action targets oracle.setBacking with ABI uint256 data. It reserves
keccak256(abi.encode(oracle,keccak256(abi.encode(setBacking selector)))) and commits
keccak256(abi.encode(selected operator,current backing)). Backing is unchanged.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-QUEUESETBACKING-11 | backing_admin | true | true | true | true | given Recovered when Queue | Success; exact authoritative state/getter assertions | Covered: [test][test_givenRecovered_whenQueue] |
| BO-QUEUESETBACKING-12 | backing_admin | true | true | false | false | given Inactive And Disabled when Queue reverts | PolicyDependency_NotActive(oracle); intent retained | Covered: [test][test_givenInactiveAndDisabled_whenQueue_reverts] |
| BO-QUEUESETBACKING-13 | backing_admin | true | true | true | true | when One reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenOne_reverts] |
| BO-QUEUESETBACKING-14 | backing_admin | true | true | true | true | when Type Maximum reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenTypeMaximum_reverts] |
| BO-QUEUESETBACKING-15 | backing_admin | true | true | true | true | when Adjacent Upper reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenAdjacentUpper_reverts] |
| BO-QUEUESETBACKING-16 | backing_admin | true | true | true | true | when Adjacent Lower reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenAdjacentLower_reverts] |
| BO-QUEUESETBACKING-01 | backing_admin | true | true | true | true | when Proposer | Success; exact authoritative state/getter assertions | Covered: [test][test_whenProposer] |
| BO-QUEUESETBACKING-02 | ADMIN | true | true | true | true | when Admin | Success; exact authoritative state/getter assertions | Covered: [test][test_whenAdmin] |
| BO-QUEUESETBACKING-03 | ADMIN + backing_admin | true | true | true | true | when Overlapping Roles | Success; exact authoritative state/getter assertions | Covered: [test][test_whenOverlappingRoles] |
| BO-QUEUESETBACKING-04 | Fuzz unauthorized | true | true | true | true | when Unauthorized reverts | NotAuthorised | Covered: [test][test_whenUnauthorized_reverts] |
| BO-QUEUESETBACKING-05 | backing_admin | true | true | true | true | when Zero reverts | BackingOracle_ZeroBacking | Covered: [test][test_whenZero_reverts] |
| BO-QUEUESETBACKING-06 | backing_admin | true | true | true | true | when Outside Bounds reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenOutsideBounds_reverts] |
| BO-QUEUESETBACKING-07 | backing_admin | true | true | true | true | when Lower Outside Bounds reverts | BackingOracle_BackingChangeTooLarge(current,new,min,max) | Covered: [test][test_whenLowerOutsideBounds_reverts] |
| BO-QUEUESETBACKING-08 | backing_admin | true | true | true | true | when Boundary Seeds | Success; exact authoritative state/getter assertions | Covered: [test][test_whenBoundarySeeds] |
| BO-QUEUESETBACKING-09 | backing_admin | true | false | true | false | given Disabled when Queue reverts | PolicyDependency_NotActive(oracle); intent retained | Covered: [test][test_givenDisabled_whenQueue_reverts] |
| BO-QUEUESETBACKING-10 | backing_admin | true | true | false | true | given Inactive when Queue reverts | PolicyDependency_NotActive(oracle); intent retained | Covered: [test][test_givenInactive_whenQueue_reverts] |
| BO-TIMELOCK-QUEUESETBACKING-03 | backing_admin | false | true | true | true | given Own Inactive when Queue reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenOwnInactive_whenQueue_reverts] |
| BO-TIMELOCK-QUEUESETBACKING-02 | backing_admin | true | false | true | true | given Own Paused when Queue reverts | NotEnabled | Covered: [test][test_givenOwnPaused_whenQueue_reverts] |
| BO-TIMELOCK-QUEUESETBACKING-01 | backing_admin | true | true | true | true | given Operator Revoked when Queue reverts | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenOperatorRevoked_whenQueue_reverts] |
| BO-REPLACEMENT-02 | backing_admin | true | true | true | true | given Pending when Conflict reverts | ConfigKeyPending(scoped backing key,owner); no leaked ID | Covered: [test][test_givenPending_whenConflict_reverts] |

[test_givenRecovered_whenQueue]: ./queueSetBacking.t.sol#L9
[test_givenInactiveAndDisabled_whenQueue_reverts]: ./queueSetBacking.t.sol#L14
[test_whenOne_reverts]: ./queueSetBacking.t.sol#L21
[test_whenTypeMaximum_reverts]: ./queueSetBacking.t.sol#L28
[test_whenAdjacentUpper_reverts]: ./queueSetBacking.t.sol#L35
[test_whenAdjacentLower_reverts]: ./queueSetBacking.t.sol#L42
[test_whenProposer]: ./queueSetBacking.t.sol#L49
[test_whenAdmin]: ./queueSetBacking.t.sol#L91
[test_whenOverlappingRoles]: ./queueSetBacking.t.sol#L97
[test_whenUnauthorized_reverts]: ./queueSetBacking.t.sol#L104
[test_whenZero_reverts]: ./queueSetBacking.t.sol#L113
[test_whenOutsideBounds_reverts]: ./queueSetBacking.t.sol#L121
[test_whenLowerOutsideBounds_reverts]: ./queueSetBacking.t.sol#L130
[test_whenBoundarySeeds]: ./queueSetBacking.t.sol#L138
[test_givenDisabled_whenQueue_reverts]: ./queueSetBacking.t.sol#L153
[test_givenInactive_whenQueue_reverts]: ./queueSetBacking.t.sol#L160
[test_givenOwnInactive_whenQueue_reverts]: ./queueSetBacking.t.sol#L167
[test_givenOwnPaused_whenQueue_reverts]: ./queueSetBacking.t.sol#L174
[test_givenOperatorRevoked_whenQueue_reverts]: ./queueSetBacking.t.sol#L183
[test_givenPending_whenConflict_reverts]: ./queueSetBacking.t.sol#L192

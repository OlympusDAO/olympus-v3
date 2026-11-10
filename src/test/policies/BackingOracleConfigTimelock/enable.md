# enable scenarios

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

EnablerV2 checks local transition state, then caller authority. Empty queue data
precedes own activity, shared constructor interface checks, same-Kernel
target membership and selected-operator checks. The target enabled getter must not be read.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-TIMELOCK-ENABLE-01 | ADMIN | true | false | true | Fuzz false/true | given Target Paused when Enable | Success; exact authoritative state/getter assertions | Covered: [test][test_givenTargetPaused_whenEnable] |
| BO-TIMELOCK-ENABLE-02 | ADMIN | true | false | true | false | given Operator Revoked when Enable reverts | NotAuthorised; pending intent/backing preserved | Covered: [test][test_givenOperatorRevoked_whenEnable_reverts] |
| BO-TIMELOCK-ENABLE-03 | ADMIN | true | false | false | Fuzz false/true | given Target Inactive when Enable | PolicyDependency_NotActive(oracle); transition and pending intent unchanged; retry after reactivation succeeds | Covered: [test][test_givenTargetInactive_whenEnable_reverts] |
| BO-TIMELOCK-ENABLE-04 | ADMIN | false | false | true | false | given Own Inactive when Enable reverts | BackingOracleTimelock_PolicyNotActive(self) | Covered: [test][test_givenOwnInactive_whenEnable_reverts] |
| BO-TIMELOCK-ENABLE-05 | ADMIN | true | false | true | false | when Each Consumed Interface Missing reverts | BackingOracleTimelock_InvalidBackingOracle | Covered: [test][test_whenEachConsumedInterfaceMissing_reverts] |
| BO-TIMELOCK-ENABLE-06 | ADMIN | true | false | true | false | when Malformed Enable Data reverts | BackingOracleTimelock_InvalidEnablerData | Covered: [test][test_whenMalformedEnableData_reverts] |
| BO-TIMELOCK-ENABLE-07 | Fuzz unauthorized callers, including zero | Fuzz false/true | false | true | true | Nonempty data and pending intent | ROLES_RequireRole(ADMIN) before payload/activity checks; no events or mutations | Covered: [unauthorized][test_givenPending_whenUnauthorized_reverts] |
| BO-TIMELOCK-ENABLE-08 | Fuzz any caller | Fuzz false/true | true | true | true | Nonempty data and pending intent | NotDisabled before authorization/payload/activity checks; no events or mutations | Covered: [already enabled][test_givenEnabled_whenEnable_reverts] |
| BO-TIMELOCK-ENABLE-09 | ADMIN | true | false | true | true | Empty data and pending intent after pause | Exact Enabled/Transition events and timestamp; complete intent/backing preserved | Covered: [transition][test_givenPending_whenAdminEnables] |

[test_givenTargetPaused_whenEnable]: ./enable.t.sol#L100
[test_givenOperatorRevoked_whenEnable_reverts]: ./enable.t.sol#L118
[test_givenTargetInactive_whenEnable_reverts]: ./enable.t.sol#L129
[test_givenOwnInactive_whenEnable_reverts]: ./enable.t.sol#L161
[test_whenEachConsumedInterfaceMissing_reverts]: ./enable.t.sol#L170
[test_whenMalformedEnableData_reverts]: ./enable.t.sol#L199
[test_givenPending_whenUnauthorized_reverts]: ./enable.t.sol#L21
[test_givenEnabled_whenEnable_reverts]: ./enable.t.sol#L48
[test_givenPending_whenAdminEnables]: ./enable.t.sol#L72

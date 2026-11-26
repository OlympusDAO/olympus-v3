# reEnable scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol`, `ReEnabler` and
`ReEnablerGracePeriod`. ADMIN is _ADMIN, backing_admin is _PROPOSER; the harness
holds neither policy role. Default grace is seven days, measured from last disable.
Reverts preserve backing, operator, enabled flag, transition timestamp and pending intent.

Inherited ordering: already-enabled state, NeverEnabled history, caller authority,
grace check, then activation prerequisites. ADMIN or backing_admin (including overlap)
may recover; unauthorized caller fuzz excludes both accepted identities and retains
zero. Valid time fuzz spans the inclusive [0,7 days] interval; equality and expiry+1
are seeded. uint48 deadline overflow must return SafeCastOverflowedUintDowncast.
Oracle recovery requires own activity and preserves backing/delegation. Queue
recovery requires own activity, a compatible same-Kernel active target and current
selection without reading target enablement. Payloads, keys and deadlines persist.

| ID | Caller | Local active | Local enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BO-TIMELOCK-REENABLE-01 | backing_admin | true | false | given Pending when Recover Preserves Intent | Success; exact state/events/preservation assertions | Covered: [test][test_givenPending_whenRecoverPreservesIntent] |
| BO-TIMELOCK-REENABLE-02 | backing_admin | false | false | given Own Inactive when Recover reverts | Own PolicyNotActive(policy) | Covered: [test][test_givenOwnInactive_whenRecover_reverts] |
| BO-TIMELOCK-REENABLE-03 | backing_admin | true | false | given Operator Revoked when Recover reverts | NotAuthorised (selection lost) | Covered: [test][test_givenOperatorRevoked_whenRecover_reverts] |
| BO-TIMELOCK-REENABLE-04 | ADMIN | true | false | given Disabled when After Deadline reverts | GracePeriod_Expired(original deadline) | Covered: [test][test_givenDisabled_whenAfterDeadline_reverts] |
| BO-TIMELOCK-REENABLE-10 | Fuzz authorized roles | true | false | given Disabled when Authorized | Success; exact state/events/preservation assertions | Covered: [test][test_givenDisabled_whenAuthorized] |
| BO-TIMELOCK-REENABLE-09 | ADMIN | true | false | given Disabled when At Deadline | Success; exact state/events/preservation assertions | Covered: [test][test_givenDisabled_whenAtDeadline] |
| BO-TIMELOCK-REENABLE-08 | ADMIN | true | true | given Enabled when Recover reverts | NotDisabled | Covered: [test][test_givenEnabled_whenRecover_reverts] |
| BO-TIMELOCK-REENABLE-07 | ADMIN | true | false | given Never Enabled when Recover reverts | NeverEnabled | Covered: [test][test_givenNeverEnabled_whenRecover_reverts] |
| BO-TIMELOCK-REENABLE-06 | Fuzz unauthorized | true | false | given Disabled when Unauthorized reverts | NotAuthorised | Covered: [test][test_givenDisabled_whenUnauthorized_reverts] |
| BO-TIMELOCK-REENABLE-05 | ADMIN | true | false | given Deadline Overflow when Recover reverts | SafeCastOverflowedUintDowncast(48, widened deadline) | Covered: [test][test_givenDeadlineOverflow_whenRecover_reverts] |
| BO-TIMELOCK-REENABLE-11 | backing_admin | true | false | Target inactive, fuzz target enabled/paused; pending intent | PolicyDependency_NotActive(oracle); no transition or intent changes; retry after target reactivation succeeds | Covered: [inactive target][test_givenTargetInactive_whenRecover_reverts] |

[test_givenPending_whenRecoverPreservesIntent]: ./reEnable.t.sol#L16
[test_givenOwnInactive_whenRecover_reverts]: ./reEnable.t.sol#L75
[test_givenOperatorRevoked_whenRecover_reverts]: ./reEnable.t.sol#L84
[test_givenDisabled_whenAfterDeadline_reverts]: ./reEnable.t.sol#L95
[test_givenDisabled_whenAuthorized]: ./reEnable.t.sol#L108
[test_givenDisabled_whenAtDeadline]: ./reEnable.t.sol#L124
[test_givenEnabled_whenRecover_reverts]: ./reEnable.t.sol#L134
[test_givenNeverEnabled_whenRecover_reverts]: ./reEnable.t.sol#L141
[test_givenDisabled_whenUnauthorized_reverts]: ./reEnable.t.sol#L153
[test_givenDeadlineOverflow_whenRecover_reverts]: ./reEnable.t.sol#L163
[test_givenTargetInactive_whenRecover_reverts]: ./reEnable.t.sol#L40

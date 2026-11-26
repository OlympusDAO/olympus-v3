# reEnable scenarios

Source: `src/policies/BackingOracle.sol`, `ReEnabler` and
`ReEnablerGracePeriod`. ADMIN is _ADMIN, backing_admin is _PROPOSER; the harness
holds neither policy role. Default grace is seven days, measured from last disable.
Reverts preserve backing, operator, enabled flag, transition timestamp and pending intent.

Inherited ordering: already-enabled state, NeverEnabled history, caller authority,
grace check, then activation prerequisites. ADMIN or backing_admin (including overlap)
may recover; unauthorized caller fuzz excludes both accepted identities and retains
zero. Valid time fuzz spans the inclusive [0,7 days] interval; equality and expiry+1
are seeded. uint48 deadline overflow must return SafeCastOverflowedUintDowncast.
Oracle recovery requires own activity and preserves backing/delegation. It does not
read the selected operator's lifecycle or metadata.

| ID | Caller | Local active | Local enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BO-REENABLE-01 | Fuzz authorized roles | true | false | given Disabled when Authorized | Success; exact state/events/preservation assertions | Covered: [test][test_givenDisabled_whenAuthorized] |
| BO-REENABLE-02 | ADMIN | true | false | given Disabled when Admin At Deadline | Success; exact state/events/preservation assertions | Covered: [test][test_givenDisabled_whenAdminAtDeadline] |
| BO-REENABLE-03 | ADMIN | true | false | given Disabled when After Deadline reverts | GracePeriod_Expired(original deadline) | Covered: [test][test_givenDisabled_whenAfterDeadline_reverts] |
| BO-REENABLE-04 | ADMIN | true | false | given Never Enabled when Recover reverts | NeverEnabled | Covered: [test][test_givenNeverEnabled_whenRecover_reverts] |
| BO-REENABLE-05 | ADMIN | true | true | given Enabled when Recover reverts | NotDisabled | Covered: [test][test_givenEnabled_whenRecover_reverts] |
| BO-REENABLE-06 | Fuzz unauthorized | true | false | given Disabled when Unauthorized reverts | NotAuthorised | Covered: [test][test_givenDisabled_whenUnauthorized_reverts] |
| BO-REENABLE-07 | backing_admin | false | false | given Inactive when Recover reverts | Own PolicyNotActive(policy) | Covered: [test][test_givenInactive_whenRecover_reverts] |
| BO-REENABLE-08 | ADMIN | true | false | given Deadline Overflow when Recover reverts | SafeCastOverflowedUintDowncast(48, widened deadline) | Covered: [test][test_givenDeadlineOverflow_whenRecover_reverts] |
| BO-REENABLE-09 | backing_admin | true | false | given Disabled when Immediately Before Deadline | Success; exact state/events/preservation assertions | Covered: [test][test_givenDisabled_whenImmediatelyBeforeDeadline] |

[test_givenDisabled_whenAuthorized]: ./reEnable.t.sol#L17
[test_givenDisabled_whenAdminAtDeadline]: ./reEnable.t.sol#L42
[test_givenDisabled_whenAfterDeadline_reverts]: ./reEnable.t.sol#L52
[test_givenNeverEnabled_whenRecover_reverts]: ./reEnable.t.sol#L65
[test_givenEnabled_whenRecover_reverts]: ./reEnable.t.sol#L72
[test_givenDisabled_whenUnauthorized_reverts]: ./reEnable.t.sol#L79
[test_givenInactive_whenRecover_reverts]: ./reEnable.t.sol#L89
[test_givenDeadlineOverflow_whenRecover_reverts]: ./reEnable.t.sol#L98
[test_givenDisabled_whenImmediatelyBeforeDeadline]: ./reEnable.t.sol#L114

# setGracePeriod scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol`, `ReEnabler` and
`ReEnablerGracePeriod`. ADMIN is _ADMIN, backing_admin is _PROPOSER; the harness
holds neither policy role. Default grace is seven days, measured from last disable.
Reverts preserve backing, operator, enabled flag, transition timestamp and pending intent.

Admission: own activity, enabled state, ADMIN, then nonzero uint32 period.
Fuzz [1,MAX32]; seed zero, one and MAX32. An unchanged valid period emits one
GracePeriodSet event, preserves transition timestamp and leaves enablement unchanged.
Target readiness and selected operator are irrelevant to this ADMIN-only setting.

| ID | Caller | Local active | Local enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BO-TIMELOCK-SETGRACEPERIOD-01 | ADMIN | true | true | when Admin Changes | Success; exact state/events/preservation assertions | Covered: [test][test_whenAdminChanges] |
| BO-TIMELOCK-SETGRACEPERIOD-02 | ADMIN | true | true | when Boundary Seeds | Success; exact state/events/preservation assertions | Covered: [test][test_whenBoundarySeeds] |
| BO-TIMELOCK-SETGRACEPERIOD-03 | ADMIN | true | true | when Zero reverts | GracePeriod_ZeroPeriod | Covered: [test][test_whenZero_reverts] |
| BO-TIMELOCK-SETGRACEPERIOD-04 | ADMIN | true | true | when Same Value | Success; exact state/events/preservation assertions | Covered: [test][test_whenSameValue] |
| BO-TIMELOCK-SETGRACEPERIOD-05 | Fuzz unauthorized | true | true | when Unauthorized reverts | ROLES_RequireRole(ADMIN) | Covered: [test][test_whenUnauthorized_reverts] |
| BO-TIMELOCK-SETGRACEPERIOD-07 | ADMIN | true | false | given Disabled when Set reverts | NotEnabled | Covered: [test][test_givenDisabled_whenSet_reverts] |
| BO-TIMELOCK-SETGRACEPERIOD-06 | ADMIN | false | true | given Inactive when Set reverts | Own PolicyNotActive(policy) | Covered: [test][test_givenInactive_whenSet_reverts] |

[test_whenAdminChanges]: ./setGracePeriod.t.sol#L15
[test_whenBoundarySeeds]: ./setGracePeriod.t.sol#L27
[test_whenZero_reverts]: ./setGracePeriod.t.sol#L36
[test_whenSameValue]: ./setGracePeriod.t.sol#L43
[test_whenUnauthorized_reverts]: ./setGracePeriod.t.sol#L52
[test_givenDisabled_whenSet_reverts]: ./setGracePeriod.t.sol#L60
[test_givenInactive_whenSet_reverts]: ./setGracePeriod.t.sol#L69

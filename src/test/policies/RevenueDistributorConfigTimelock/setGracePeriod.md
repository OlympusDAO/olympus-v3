# RevenueDistributorConfigTimelock.setGracePeriod scenario plan

The concrete setter requires own Kernel activity before inherited local enablement, ADMIN authorization and nonzero-period validation. Same valid periods retain the inherited single-event behavior and do not alter lifecycle history.

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: inherited setGracePeriod action and co-located gracePeriod assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributorConfigTimelock; own inactivity uses `RevenueDistributorConfigTimelock_PolicyNotActive(this policy)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin only; fuzz unauthorized callers excluding every Admin identity.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Every valid call stores the requested uint32 period and emits GracePeriodSet once, including same-value inputs inherited from ReEnablerGracePeriod. Preserve isEnabled, lastTransitionAt, configuration/debt/custody. Check gracePeriod independently against the supplied input.

## Grace period

| ID | Caller | Local active | Local enabled | `period_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-GRACE-P04 | ADMIN_ROLE holder | true | true | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | Success | `gracePeriod` equals input; one GracePeriodSet; transition timestamp unchanged | Covered: [fuzz][test_whenAdminSetsNonzeroPeriod_storesValue], [boundaries][test_whenBoundaryPeriodsSet_storesEachValue] |
| RDCT-GRACE-P05 | ADMIN_ROLE holder | true | true | Current valid period | Success | Stored value and transition timestamp unchanged; one GracePeriodSet emitted | Covered: [test][test_givenCurrentGrace_whenAdminSetsSameValue], [test][test_givenGraceSetterBoundarySeeds] |
| RDCT-GRACE-P06 | ADMIN_ROLE holder | false | true | Current valid period | RevenueDistributorConfigTimelock_PolicyNotActive(this policy) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenAdminChangesGrace_reverts] |
| RDCT-GRACE-I03 | ADMIN_ROLE holder | true | true | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [evidence][test_whenAdminSetsZeroPeriod_reverts] |
| RDCT-GRACE-L01 | Fuzz all callers | true | false | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | NotEnabled() before authorization/input validation | Unchanged | Covered: [test][test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts], [test][test_givenGraceSetterBoundarySeeds] |
| RDCT-GRACE-L03 | Fuzz all callers | false | false | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | Unchanged | Covered: [test][test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts], [test][test_givenGraceSetterBoundarySeeds] |
| RDCT-GRACE-A04 | Any non-admin, fuzz | true | true | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | ROLES_RequireRole(ADMIN_ROLE) before numeric validation | Unchanged | Covered: [evidence][test_whenNonAdminSetsPeriod_reverts] |
| RDCT-GRACE-L02 | ADMIN_ROLE holder | false | true | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | RevenueDistributorConfigTimelock_PolicyNotActive(this policy) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenAdminChangesGrace_reverts] |

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDCT-GRACE-L04 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; fuzz full uint32 period | RevenueDistributorConfigTimelock_PolicyNotActive(TL) | Period, enabled flag, transition timestamp and preserved state unchanged | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts] |

[test_whenAdminSetsNonzeroPeriod_storesValue]: ./setGracePeriod.t.sol#L33
[test_whenBoundaryPeriodsSet_storesEachValue]: ./setGracePeriod.t.sol#L19
[test_whenAdminSetsZeroPeriod_reverts]: ./setGracePeriod.t.sol#L63
[test_whenNonAdminSetsPeriod_reverts]: ./setGracePeriod.t.sol#L88
[test_givenInactivePolicy_whenAdminChangesGrace_reverts]: ./setGracePeriod.t.sol#L100
[test_givenCurrentGrace_whenAdminSetsSameValue]: ./setGracePeriod.t.sol#L125
[test_givenGraceSetterBoundarySeeds]: ./setGracePeriod.t.sol#L219
[test_givenActiveDisabled_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L156
[test_givenInactiveDisabled_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L184
[test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L240

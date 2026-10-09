# RevenueDistributorTask.setGracePeriod scenario plan

Scope: inherited setGracePeriod action and co-located gracePeriod assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only; fuzz unauthorized callers excluding every Admin identity.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Every valid call stores the requested uint32 period and emits GracePeriodSet once, including same-value inputs inherited from ReEnablerGracePeriod. Preserve isEnabled, lastTransitionAt, configuration/debt/custody. Check gracePeriod independently against the supplied input.

## Grace period

| ID | Caller | Task Kernel | Task local | `period_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LC-P04 | Admin | Active | Enabled | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | Success | `gracePeriod` equals input; one GracePeriodSet; transition timestamp unchanged | Covered: [range][test_whenAdminSetsPositiveGracePeriod_updatesValue] |
| LC-P05 | Admin | Fuzz active/inactive | Enabled | Current valid period | Success | Stored value and transition timestamp unchanged; one GracePeriodSet emitted | Covered: [test][test_whenAdminSetsCurrentGracePeriod_emitsEvent] |
| LC-I03 | Admin | Active | Enabled | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [test][test_whenAdminSetsZeroGracePeriod_reverts] |
| LC-L01 | Admin and non-admin separately | Active or inactive | Disabled | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | NotEnabled() before authorization/input validation | Unchanged | Covered: [test][test_givenDisabled_whenGracePeriodSet_revertsBeforeOtherChecks] |
| LC-A04 | Any non-admin, fuzz | Active | Enabled | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | ROLES_RequireRole(ADMIN_ROLE) before numeric validation | Unchanged | Covered: [test][test_givenEnabled_whenNonAdminSetsGracePeriod_reverts] |
| LC-L02 | Admin with role retained | Inactive | Enabled | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | Success | `gracePeriod` equals input; one GracePeriodSet; transition timestamp, dependencies and all other state unchanged | Covered: [test][test_whenAdminSetsPositiveGracePeriod_updatesValue] |

[test_whenAdminSetsPositiveGracePeriod_updatesValue]: ./setGracePeriod.t.sol#L12
[test_whenAdminSetsCurrentGracePeriod_emitsEvent]: ./setGracePeriod.t.sol#L45
[test_whenAdminSetsZeroGracePeriod_reverts]: ./setGracePeriod.t.sol#L34
[test_givenDisabled_whenGracePeriodSet_revertsBeforeOtherChecks]: ./setGracePeriod.t.sol#L60
[test_givenEnabled_whenNonAdminSetsGracePeriod_reverts]: ./setGracePeriod.t.sol#L77

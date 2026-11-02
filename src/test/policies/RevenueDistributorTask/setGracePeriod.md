# RevenueDistributorTask.setGracePeriod scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: inherited setGracePeriod action and co-located gracePeriod assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributorTask; own inactivity uses `RevenueDistributorTask_PolicyNotActive(Task)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Admin only; fuzz unauthorized callers excluding every Admin identity.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Every valid call stores the requested uint32 period and emits GracePeriodSet once, including same-value inputs inherited from ReEnablerGracePeriod. Preserve isEnabled, lastTransitionAt, configuration/debt/custody. Check gracePeriod independently against the supplied input.

## Grace period

| ID | Caller | Local active | Local enabled | `period_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GRACE-P04 | ADMIN_ROLE holder | true | true | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | Success | `gracePeriod` equals input; one GracePeriodSet; transition timestamp unchanged | Covered: [range][test_whenAdminSetsPositiveGracePeriod_updatesValue] |
| RDTASK-GRACE-P05 | ADMIN_ROLE holder | true | true | Current valid period | Success | Stored value and transition timestamp unchanged; one GracePeriodSet emitted | Covered: [test][test_givenCurrentGrace_whenAdminSetsSameValue], [test][test_givenGraceSetterBoundarySeeds] |
| RDTASK-GRACE-P06 | ADMIN_ROLE holder | false | true | Current valid period | RevenueDistributorTask_PolicyNotActive(Task) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenAdminChangesGrace_reverts] |
| RDTASK-GRACE-I03 | ADMIN_ROLE holder | true | true | 0 | GracePeriod_ZeroPeriod() | Unchanged | Covered: [test][test_whenAdminSetsZeroGracePeriod_reverts] |
| RDTASK-GRACE-L01 | Fuzz all callers | true | false | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | NotEnabled() before authorization/input validation | Unchanged | Covered: [test][test_givenDisabled_whenAnyCallerSetsGrace_reverts], [test][test_givenGraceSetterBoundarySeeds] |
| RDTASK-GRACE-L03 | Fuzz all callers | false | false | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | RevenueDistributorTask_PolicyNotActive(Task) before local enablement, caller and input checks | Unchanged | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst], [test][test_givenGraceSetterBoundarySeeds] |
| RDTASK-GRACE-A04 | Any non-admin, fuzz | true | true | Fuzz 0..`type(uint32).max`; seed 0, 1 and MAX | ROLES_RequireRole(ADMIN_ROLE) before numeric validation | Unchanged | Covered: [test][test_givenEnabled_whenNonAdminSetsGracePeriod_reverts] |
| RDTASK-GRACE-L02 | ADMIN_ROLE holder | false | true | Fuzz 1..`type(uint32).max` excluding current; seed 1 and MAX | RevenueDistributorTask_PolicyNotActive(Task) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenAdminChangesGrace_reverts] |

[test_whenAdminSetsPositiveGracePeriod_updatesValue]: ./setGracePeriod.t.sol#L23

[test_whenAdminSetsZeroGracePeriod_reverts]: ./setGracePeriod.t.sol#L41

[test_givenEnabled_whenNonAdminSetsGracePeriod_reverts]: ./setGracePeriod.t.sol#L101
[test_givenInactivePolicy_whenAdminChangesGrace_reverts]: ./setGracePeriod.t.sol#L116

[test_givenCurrentGrace_whenAdminSetsSameValue]: ./setGracePeriod.t.sol#L135

[test_givenGraceSetterBoundarySeeds]: ./setGracePeriod.t.sol#L225

[test_givenDisabled_whenAnyCallerSetsGrace_reverts]: ./setGracePeriod.t.sol#L162

[test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_revertsActivityFirst]: ./setGracePeriod.t.sol#L191

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-GRACE-L04 | Any address, fuzz, without authorization exclusions | false | false | Task locally disabled, then Kernel-deactivated; Fuzz full `uint32` input type without bounds/exclusions | `RevenueDistributorTask_PolicyNotActive(task)` before local enablement (where required), caller and input checks | Revert; no effects of the attempted action commit. Grace period is explicitly asserted unchanged. | Covered: [test][test_givenInactiveAndDisabled_whenGracePeriodSet_revertsBeforeOtherChecks] |

[test_givenInactiveAndDisabled_whenGracePeriodSet_revertsBeforeOtherChecks]: ./setGracePeriod.t.sol#L80

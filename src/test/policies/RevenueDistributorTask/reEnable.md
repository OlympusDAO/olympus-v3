# RevenueDistributorTask.reEnable scenario plan

Scope: inherited reEnable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted
role classes. Bound RD must be Kernel-active and locally enabled or give
`RevenueDistributorTask_InvalidDistributor(RD)`. The re-enable hook validates both independent RD
lifecycle axes. `NeverEnabled()` is the upstream `ReEnabler`
error for `lastTransitionAt == 0`.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Re-enable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P03 | Admin; Revenue Distributor Admin separately | Previously enabled then disabled; RD Kernel-active and locally enabled; time at disable, deadline-1, deadline | reEnable succeeds | Re-enable with empty Transition data; preserve configuration | Covered: [test][test_givenDisabledWithinGrace_whenPermittedCallerReEnables] |
| LC-I02 | Authorized reEnable caller | Never previously enabled | NeverEnabled() | Unchanged | Covered: [test][test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts] |
| LC-A02 | Unauthorized caller, fuzz | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerReEnables_reverts] |
| LC-I06 | Authorized reEnable caller | Already enabled | NotDisabled() | Unchanged | Covered: [test][test_givenEnabled_whenReEnabled_reverts] |
| LC-I07 | Authorized reEnable caller | Previously enabled then disabled; fuzz `now` over `[grace deadline + 1, type(uint48).max]`, with both endpoints guaranteed | GracePeriod_Expired(deadline) | Unchanged | Covered: [test][test_givenGraceExpired_whenAdminReEnables_reverts] |
| LC-L02 | Admin; Revenue Distributor Admin separately, roles retained | Own task deactivated after dependency configuration; previously enabled then disabled; within grace; bound RD Kernel-active and locally enabled | reEnable succeeds | Re-enable and timestamp/events; cached dependencies, gas settings, cursor and balances remain unchanged | Covered: [test][test_givenDisabledWithinGrace_whenPermittedCallerReEnables] |

## Dependency hook failures

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-I04 | Authorized reEnable caller | Own task active or inactive; bound RD Kernel-inactive and local state fuzzed; otherwise valid task state and within grace | RevenueDistributorTask_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [test][test_givenDistributorInactive_whenPermittedCallerReEnables_reverts] |
| LC-I05 | Authorized reEnable caller | Own task active or inactive; bound RD Kernel-active but locally disabled; otherwise valid task state and within grace | RevenueDistributorTask_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [test][test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts] |

[test_givenDisabledWithinGrace_whenPermittedCallerReEnables]: ./reEnable.t.sol#L14
[test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L45
[test_givenDisabled_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L57
[test_givenEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L73
[test_givenGraceExpired_whenAdminReEnables_reverts]: ./reEnable.t.sol#L80
[test_givenDistributorInactive_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L98
[test_givenDistributorDisabled_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L116

# RevenueDistributor.reEnable scenario plan

Scope: inherited reEnable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted role classes. No target-policy compatibility hook applies.

`NeverEnabled()` is the upstream `ReEnabler` error for the distinct initial state where `lastTransitionAt == 0`; retain it rather than collapsing that state into the already-enabled `NotDisabled()` error.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Re-enable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P03 | Admin; Revenue Distributor Admin separately | Previously enabled then disabled; within grace, including exact deadline | reEnable succeeds | Re-enable; preserve configuration and stored balances | Covered: [admin route preservation][test_givenDisabled_whenReEnabled_thenStoredBalanceDistributes], [Revenue Distributor Admin][test_givenDistributorDisabled_whenRevenueAdminReEnables_thenDistributionResumes], [deadline][test_givenGraceDeadline_whenAdminReEnables_succeeds] |
| LC-I02 | Authorized reEnable caller | Never previously enabled | NeverEnabled() | Unchanged | Covered: [evidence][test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts] |
| LC-A02 | Unauthorized caller, fuzz | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Unchanged | Covered: [evidence][test_givenDistributorDisabled_whenUnauthorizedCallerReEnables_reverts] |
| LC-I06 | Authorized reEnable caller | Already enabled | NotDisabled() | Unchanged | Covered: [evidence][test_givenEnabled_whenReEnabled_reverts] |
| LC-I07 | Authorized reEnable caller | Previously enabled then disabled; exact grace deadline + 1 | GracePeriod_Expired(deadline) | Unchanged | Covered: [evidence][test_givenGraceExpired_whenAdminReEnables_reverts] |
| LC-L02 | Admin; Revenue Distributor Admin separately, roles retained | Own policy deactivated after dependency configuration; previously enabled then disabled; within grace | reEnable succeeds | Re-enable; cached dependencies and configuration remain unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenPermittedCallerReEnables_succeeds] |

[test_givenDisabled_whenReEnabled_thenStoredBalanceDistributes]: ./reEnable.t.sol#L53
[test_givenDistributorDisabled_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L35
[test_givenDistributorDisabled_whenRevenueAdminReEnables_thenDistributionResumes]: ./reEnable.t.sol#L18
[test_givenGraceDeadline_whenAdminReEnables_succeeds]: ./reEnable.t.sol#L91
[test_givenNeverEnabled_whenAuthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L70
[test_givenEnabled_whenReEnabled_reverts]: ./reEnable.t.sol#L84
[test_givenGraceExpired_whenAdminReEnables_reverts]: ./reEnable.t.sol#L105
[test_givenPolicyInactiveAndDisabled_whenPermittedCallerReEnables_succeeds]: ./reEnable.t.sol#L121

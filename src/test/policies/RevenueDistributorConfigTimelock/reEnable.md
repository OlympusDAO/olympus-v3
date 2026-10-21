# RevenueDistributorConfigTimelock.reEnable scenario plan

Scope: inherited reEnable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Revenue Distributor Admin, separately; fuzz unauthorized callers excluding both permitted role classes. RD.kernel must equal RDT.kernel; mismatch gives RevenueDistributorConfigTimelock_InvalidDistributor(RD). RD local disablement or inactivity is otherwise permitted by this hook. `NeverEnabled()` is the upstream `ReEnabler` error for `lastTransitionAt == 0`.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,emptyData,timestamp). Preserve configuration/debt/custody. Grace starts at the prior disable timestamp; its exact deadline is allowed.

## Re-enable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P03 | Admin; Revenue Distributor Admin separately | Previously enabled then disabled; time at disable, deadline-1, deadline; compatible hook states | reEnable succeeds | Re-enable with empty Transition data; preserve configuration | Covered: [window and roles][testFuzz_whenPermittedCallerReEnablesWithinGrace_recordsTransition], [deadline][test_whenExactGraceDeadline_reenables] |
| LC-I02 | Authorized reEnable caller | Never previously enabled | NeverEnabled() | Unchanged | Covered: [evidence][test_whenNeverEnabled_reverts] |
| LC-A02 | Unauthorized caller, fuzz | Disabled within grace; excludes admin and every granted Revenue Distributor Admin | NotAuthorised() | Unchanged | Covered: [evidence][testFuzz_whenUnauthorizedCallerReEnables_reverts] |
| LC-I06 | Authorized reEnable caller | Already enabled | NotDisabled() | Unchanged | Covered: [evidence][testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization] |
| LC-I07 | Authorized reEnable caller | Previously enabled then disabled; fuzz `now` over `[grace deadline + 1, type(uint48).max]`, with both endpoints guaranteed | GracePeriod_Expired(deadline) | Unchanged | Covered: [evidence][testFuzz_whenGracePeriodExpired_reverts] |
| LC-L02 | Admin; Revenue Distributor Admin separately, roles retained | Own policy deactivated after dependency configuration; previously enabled then disabled; within grace; RD still reports the same Kernel | reEnable succeeds | Re-enable and timestamp/events; cached dependencies, queue state and target state remain unchanged | Covered: [evidence][testFuzz_whenOwnPolicyInactive_permittedCallerCanReEnable] |

## Dependency hook failures

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-I04 | Authorized reEnable caller | Own policy active or inactive; bound RD reports a different Kernel; otherwise valid local state and within grace | RevenueDistributorConfigTimelock_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [evidence][testFuzz_whenDistributorKernelMismatches_reverts] |

[testFuzz_whenPermittedCallerReEnablesWithinGrace_recordsTransition]: ./reEnable.t.sol
[test_whenExactGraceDeadline_reenables]: ./reEnable.t.sol#L56
[test_whenNeverEnabled_reverts]: ./reEnable.t.sol#L72
[testFuzz_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol
[testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization]: ./reEnable.t.sol
[testFuzz_whenGracePeriodExpired_reverts]: ./reEnable.t.sol
[testFuzz_whenOwnPolicyInactive_permittedCallerCanReEnable]: ./reEnable.t.sol
[testFuzz_whenDistributorKernelMismatches_reverts]: ./reEnable.t.sol

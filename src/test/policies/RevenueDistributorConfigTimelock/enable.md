# RevenueDistributorConfigTimelock.enable scenario plan

Scope: inherited enable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only; fuzz unauthorized callers excluding every Admin identity. RD.kernel must equal RDT.kernel; mismatch gives RevenueDistributorConfigTimelock_InvalidDistributor(RD). RD local disablement or inactivity is otherwise permitted by this hook.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,data,timestamp). Preserve existing configuration/debt/custody. Test empty and nonempty enable data.

## Enable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P01 | Admin | Never enabled or previously disabled; empty/nonempty arbitrary enable data; each compatible hook state | enable succeeds | Enable and timestamp/events; preserve existing configuration, debt and balances | Covered: [fresh][test_whenNeverEnabled_adminCanEnable], [previously disabled][testFuzz_whenAdminEnablesDisabledPolicy_recordsTransition] |
| LC-I01 | Any caller, fuzz | enable while already enabled; otherwise valid data | NotDisabled() before authorization | Unchanged | Covered: [evidence][testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization] |
| LC-A01 | Non-admin, fuzz | Disabled; enable hook otherwise valid; exclude all admins | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [evidence][testFuzz_whenNonAdminEnables_reverts] |
| LC-L02 | Admin, roles retained | Own policy deactivated after dependency configuration; disabled; RD still reports the same Kernel | enable succeeds | Enable and timestamp/events; cached dependencies, queue state and target state remain unchanged | Covered: [evidence][testFuzz_whenAdminEnablesDisabledPolicy_recordsTransition] |

## Dependency hook failures

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-I04 | Authorized enable caller | Own policy active or inactive; bound RD reports a different Kernel; otherwise valid local state | RevenueDistributorConfigTimelock_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [evidence][testFuzz_whenDistributorKernelMismatches_reverts] |

[test_whenNeverEnabled_adminCanEnable]: ./enable.t.sol#L108
[testFuzz_whenAdminEnablesDisabledPolicy_recordsTransition]: ./enable.t.sol
[testFuzz_whenAlreadyEnabled_revertsBeforeAuthorization]: ./enable.t.sol
[testFuzz_whenNonAdminEnables_reverts]: ./enable.t.sol
[testFuzz_whenDistributorKernelMismatches_reverts]: ./enable.t.sol

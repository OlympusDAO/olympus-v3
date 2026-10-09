# RevenueDistributorTask.enable scenario plan

Scope: inherited enable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only; fuzz unauthorized callers excluding every Admin identity. Bound RD must be
Kernel-active and locally enabled or give `RevenueDistributorTask_InvalidDistributor(RD)`.
The enable hook validates both independent RD lifecycle axes.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,data,timestamp). Preserve existing configuration/debt/custody. Test empty and nonempty enable data.

## Enable

| ID | Caller | Task Kernel | Task local/history | RD Kernel | RD local | Enable data | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LC-P01 | Admin | Active | Never enabled or previously disabled | Active | Enabled | Empty/nonempty arbitrary bytes | enable succeeds | Enable and timestamp/events; preserve existing configuration, debt and balances | Covered: [disabled][test_givenDisabled_whenAdminEnables_preservesConfiguration], [fresh][test_givenNeverEnabled_whenAdminEnables] |
| LC-I01 | Any caller, fuzz | Fuzz active/inactive | Enabled | Fuzz active/inactive | Fuzz enabled/disabled | Empty/nonempty arbitrary bytes | NotDisabled() before authorization and dependency validation | Unchanged | Covered: [test][test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks] |
| LC-A01 | Non-admin, fuzz; exclude all admins | Fuzz active/inactive | Disabled | Active | Enabled | Empty/nonempty arbitrary bytes | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_givenDisabled_whenNonAdminEnables_reverts] |
| LC-L02 | Admin, roles retained | Inactive after dependency configuration | Disabled | Active | Enabled | Empty/nonempty arbitrary bytes | enable succeeds | Enable and timestamp/events; cached dependencies, gas settings, cursor and balances remain unchanged | Covered: [test][test_givenDisabled_whenAdminEnables_preservesConfiguration] |

## Dependency hook failures

| ID | Caller | Task Kernel | Task local | RD Kernel | RD local | Enable data | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LC-I04 | Admin | Fuzz active/inactive | Disabled | Inactive | Fuzz enabled/disabled | Valid arbitrary bytes | RevenueDistributorTask_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [test][test_givenDistributorInactive_whenAdminEnables_reverts] |
| LC-I05 | Admin | Fuzz active/inactive | Disabled | Active | Disabled | Valid arbitrary bytes | RevenueDistributorTask_InvalidDistributor(RD) | Unchanged; no transition events | Covered: [test][test_givenDistributorDisabled_whenAdminEnables_reverts] |

[test_givenDisabled_whenAdminEnables_preservesConfiguration]: ./enable.t.sol#L13
[test_givenNeverEnabled_whenAdminEnables]: ./enable.t.sol#L40
[test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks]: ./enable.t.sol#L51
[test_givenDisabled_whenNonAdminEnables_reverts]: ./enable.t.sol#L69
[test_givenDistributorInactive_whenAdminEnables_reverts]: ./enable.t.sol#L88
[test_givenDistributorDisabled_whenAdminEnables_reverts]: ./enable.t.sol#L105

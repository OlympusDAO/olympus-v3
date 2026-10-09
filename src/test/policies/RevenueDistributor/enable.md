# RevenueDistributor.enable scenario plan

Scope: inherited enable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin only; fuzz unauthorized callers excluding every Admin identity. No target-policy compatibility hook applies.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=true and lastTransitionAt to the uint48 timestamp; emits Enabled plus Transition(caller,true,data,timestamp). Preserve existing configuration/debt/custody. Test empty and nonempty enable data.

## Enable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P01 | Admin | Previously disabled; fuzz empty/nonempty enable data | enable succeeds | Enable and timestamp/events; preserve existing configuration, debt and balances | Covered: [evidence][test_givenDisabled_whenAdminEnables_preservesConfiguration] |
| LC-I01 | Any caller, fuzz | enable while already enabled; otherwise valid data | NotDisabled() before authorization | Unchanged | Covered: [evidence][test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization] |
| LC-A01 | Non-admin, fuzz | Disabled; enable hook otherwise valid; exclude all admins | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [evidence][test_givenDisabled_whenNonAdminEnables_reverts] |
| LC-L02 | Admin, roles retained | Own policy deactivated after dependency configuration; disabled | enable succeeds | Enable; cached dependencies and configuration remain unchanged | Covered: [evidence][test_givenPolicyInactiveAndDisabled_whenAdminEnables_succeeds] |

[test_givenDisabled_whenAdminEnables_preservesConfiguration]: ./enable.t.sol#L13
[test_givenEnabled_whenEnableCalled_revertsBeforeAuthorization]: ./enable.t.sol#L37
[test_givenDisabled_whenNonAdminEnables_reverts]: ./enable.t.sol#L44
[test_givenPolicyInactiveAndDisabled_whenAdminEnables_succeeds]: ./enable.t.sol#L57

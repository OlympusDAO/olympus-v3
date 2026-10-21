# RevenueDistributorTask.disable scenario plan

Scope: inherited disable action and co-located isEnabled/lastTransitionAt assertions.

Kernel activity is not an inherited `PolicyEnabler` gate. In inactive-policy rows, snapshot after deactivation so the cached ROLES module and caller roles remain available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Emergency, separately; fuzz unauthorized callers excluding all Admin and Emergency identities.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=false and lastTransitionAt to the uint48 timestamp; emits Disabled plus Transition(caller,false,data,timestamp). Preserve existing configuration/debt/custody and queued actions. Test empty and nonempty disable data.

## Disable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P02 | Admin; Emergency separately | Enabled; empty/nonempty disable data; own policy active | disable succeeds | Disable and timestamp/events; no payout or queue cancellation | Covered: [test][test_whenPermittedCallerDisables_preservesConfiguration] |
| LC-I05 | Any caller, fuzz | disable while already disabled | NotEnabled() before authorization | Unchanged | Covered: [test][test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization] |
| LC-A03 | Unauthorized caller, fuzz | Enabled; exclude all Admin and Emergency identities; call disable | NotAuthorised() | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerDisables_reverts] |
| LC-L02 | Admin; Emergency separately, roles retained | Enabled task is deactivated after dependency configuration; empty/nonempty disable data | disable succeeds | Disable and timestamp/events; cached dependencies, gas settings, cursor and balances remain unchanged | Covered: [test][test_whenPermittedCallerDisables_preservesConfiguration] |

[test_whenPermittedCallerDisables_preservesConfiguration]: ./disable.t.sol#L11
[test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization]: ./disable.t.sol#L39
[test_givenEnabled_whenUnauthorizedCallerDisables_reverts]: ./disable.t.sol#L55

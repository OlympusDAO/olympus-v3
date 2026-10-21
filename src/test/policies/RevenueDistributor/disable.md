# RevenueDistributor.disable scenario plan

Scope: inherited disable action and co-located isEnabled/lastTransitionAt assertions.

Default: the acting policy is Kernel-active. The Kernel-inactive case snapshots after deactivation, which leaves the previously cached ROLES module available. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Admin or Emergency, separately; fuzz unauthorized callers excluding all Admin and Emergency identities. The inherited action does not check the policy's Kernel-active state. A freshly deployed, never-activated policy is already disabled, so `disable` reverts with `NotEnabled()` before attempting authorization through its unset ROLES dependency.

Unchanged means lifecycle state, configuration, liabilities and balances retain their pre-call values; a reverted transaction commits no events. Match exact errors and check getters from fuzzed callers, including while disabled/inactive. Success sets isEnabled=false and lastTransitionAt to the uint48 timestamp; emits Disabled plus Transition(caller,false,data,timestamp). Preserve existing configuration/debt/custody and queued actions. Test empty and nonempty disable data.

## Disable

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| LC-P02 | Admin; Emergency separately | Enabled; fuzz empty/nonempty disable data; own policy active | disable succeeds | Disable and timestamp/events; no payout or queue cancellation | Covered: [evidence][test_whenPermittedCallerDisables_preservesConfiguration] |
| LC-I05 | Any caller, fuzz | disable while already disabled | NotEnabled() before authorization | Unchanged | Covered: [evidence][test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization] |
| LC-A03 | Unauthorized caller, fuzz | Enabled; exclude all Admin and Emergency identities; call disable | NotAuthorised() | Unchanged | Covered: [evidence][test_givenEnabled_whenUnauthorizedCallerDisables_reverts] |
| LC-L02 | Admin; Emergency separately, roles retained | Enabled policy is deactivated after dependency configuration | disable succeeds | Disable; cached dependencies and configuration remain unchanged | Covered: [evidence][test_givenPolicyInactive_whenPermittedCallerDisables_succeeds] |

[test_whenPermittedCallerDisables_preservesConfiguration]: ./disable.t.sol#L12
[test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization]: ./disable.t.sol#L38
[test_givenEnabled_whenUnauthorizedCallerDisables_reverts]: ./disable.t.sol#L50
[test_givenPolicyInactive_whenPermittedCallerDisables_succeeds]: ./disable.t.sol#L62

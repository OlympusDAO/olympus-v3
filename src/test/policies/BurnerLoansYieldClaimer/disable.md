# BurnerLoansYieldClaimer.disable coverage plan

Scope: admin and emergency disablement plus lifecycle state retention.

The enabled-state check precedes authorization. Disablement is not gated by either the claimer's or
Burner Loans' Kernel-active state, and the payload is used only in the emitted `Transition` event.

## Scenarios

| ID | Caller | Claimer local state | Claimer/target Kernel state | Payload | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-DISABLE-P01 | Admin | Enabled | Fuzz each active/inactive combination | Empty/nonempty | Success | `isEnabled = false`; timestamp becomes now; exact `Disabled` and `Transition` events; configuration and cursor unchanged | Covered: [test][test_whenPermittedCallerDisables_preservesConfiguration] |
| BLYC-DISABLE-P02 | Emergency | Enabled | Fuzz each active/inactive combination | Empty/nonempty | Success | Same transition effects as P01 | Covered: [test][test_whenPermittedCallerDisables_preservesConfiguration] |
| BLYC-DISABLE-A01 | Any caller outside admin and emergency, fuzz | Enabled | Fuzz each active/inactive combination | Empty/nonempty | `NotAuthorised()` | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerDisables_reverts] |
| BLYC-DISABLE-I01 | Any caller | Disabled | Any | Empty/nonempty | `NotEnabled()` before authorization | Unchanged | Covered: [test][test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization] |

[test_whenPermittedCallerDisables_preservesConfiguration]: ./disable.t.sol#L16
[test_givenEnabled_whenUnauthorizedCallerDisables_reverts]: ./disable.t.sol#L54
[test_givenDisabled_whenDisableCalled_revertsBeforeAuthorization]: ./disable.t.sol#L75

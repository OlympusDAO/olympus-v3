# BurnerLoansYieldClaimer.enable coverage plan

Scope: initial and subsequent admin enablement, including the inherited lifecycle getters.

The disabled-state check precedes authorization and target validation. A permitted transition
requires the constructor-bound Burner Loans policy to be Kernel-active, but does not require the
claimer itself to be Kernel-active. The calldata payload has no configuration meaning, though it is
reported unchanged by `Transition`.

## Scenarios

| ID | Caller | Claimer history/state | Claimer Kernel state | Burner Loans Kernel state | Payload | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-P01 | Admin | Previously enabled, now disabled | Fuzz active/inactive | Active | Empty/nonempty | Success | `isEnabled = true`; timestamp becomes now; exact `Enabled` and `Transition` events; configuration and cursor unchanged | Covered: [test][test_givenDisabled_whenAdminEnables_preservesConfiguration] |
| BLYC-ENABLE-P02 | Admin | Freshly deployed and never enabled | Fuzz active/inactive | Active | Empty/nonempty | Success | Same transition effects as P01; establishes the first nonzero transition timestamp | Covered: [test][test_givenNeverEnabled_whenAdminEnables] |
| BLYC-ENABLE-I01 | Any caller | Enabled | Any | Active/inactive | Empty/nonempty | `NotDisabled()` before authorization or target validation | Unchanged | Covered: [test][test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks] |
| BLYC-ENABLE-A01 | Any non-admin, fuzz | Disabled | Fuzz active/inactive | Active | Empty/nonempty | `ROLES_RequireRole(ADMIN)` | Unchanged | Covered: [test][test_givenDisabled_whenCallerWithoutAdminRoleEnables_reverts] |
| BLYC-ENABLE-I02 | Admin | Disabled | Fuzz active/inactive | Inactive | Empty/nonempty | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | Unchanged | Covered: [test][test_givenBurnerLoansPolicyInactive_whenAdminEnables_reverts] |

[test_givenDisabled_whenAdminEnables_preservesConfiguration]: ./enable.t.sol#L21
[test_givenNeverEnabled_whenAdminEnables]: ./enable.t.sol#L55
[test_givenEnabled_whenEnableCalled_revertsBeforeOtherChecks]: ./enable.t.sol#L100
[test_givenDisabled_whenCallerWithoutAdminRoleEnables_reverts]: ./enable.t.sol#L82
[test_givenBurnerLoansPolicyInactive_whenAdminEnables_reverts]: ./enable.t.sol#L120

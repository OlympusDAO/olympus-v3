# BurnerLoansYieldClaimer.reEnable coverage plan

Scope: grace-bounded re-enablement by either accepted authority.

Validation order is local disabled state, prior enablement, authorization, grace deadline, then
Burner Loans Kernel activity. The deadline is inclusive. Re-enablement does not require the claimer
itself to be Kernel-active.

## Scenarios

| ID | Caller | Claimer history/state | Claimer Kernel state | Burner Loans state | Time | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-P01 | Burner Loans admin | Previously enabled, now disabled | Fuzz active/inactive | Active | Fuzz disable time through exact deadline | Success | `isEnabled = true`; timestamp becomes now; exact `Enabled` and empty-data `Transition`; configuration/cursor unchanged | Covered: [test][test_givenDisabledWithinGrace_whenPermittedCallerReEnables] |
| BLYC-REENABLE-P02 | Admin | Previously enabled, now disabled | Fuzz active/inactive | Active | Disable time through exact deadline | Success | Same transition effects as P01 | Covered: [test][test_givenDisabledWithinGrace_whenPermittedCallerReEnables] |
| BLYC-REENABLE-I01 | Any caller | Enabled | Any | Active/inactive | Any | `NotDisabled()` before history, authorization, grace, or target checks | Unchanged | Covered: [test][test_givenEnabled_whenReEnableCalled_revertsBeforeOtherChecks] |
| BLYC-REENABLE-I02 | Any caller | Freshly deployed; disabled and never enabled | Any | Active/inactive | Any | `NeverEnabled()` before authorization, grace, or target checks | Unchanged | Covered: [test][test_givenNeverEnabled_whenReEnableCalled_revertsBeforeOtherChecks] |
| BLYC-REENABLE-A01 | Any caller outside admin and Burner Loans admin, fuzz | Previously enabled, now disabled | Fuzz active/inactive | Active | Within grace | `NotAuthorised()` | Unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerReEnables_reverts] |
| BLYC-REENABLE-I03 | Each permitted caller | Previously enabled, now disabled | Fuzz active/inactive | Inactive | Within grace | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | Unchanged | Covered: [test][test_givenBurnerLoansPolicyInactive_whenPermittedCallerReEnables_reverts] |
| BLYC-REENABLE-I04 | Each permitted caller | Previously enabled, now disabled | Fuzz active/inactive | Active | Strictly after deadline; seed deadline+1 and max practical timestamp | `GracePeriod_Expired(deadline)` | Unchanged | Covered: [test][test_givenGraceExpired_whenPermittedCallerReEnables_reverts] |
| BLYC-REENABLE-I05 | Each permitted caller | Previously enabled, now disabled | Any | Inactive | Strictly after deadline | `GracePeriod_Expired(deadline)` before target validation | Unchanged | Covered: [test][test_givenGraceExpiredAndTargetInactive_revertsBeforeTargetValidation] |

[test_givenDisabledWithinGrace_whenPermittedCallerReEnables]: ./reEnable.t.sol#L22
[test_givenEnabled_whenReEnableCalled_revertsBeforeOtherChecks]: ./reEnable.t.sol#L69
[test_givenNeverEnabled_whenReEnableCalled_revertsBeforeOtherChecks]: ./reEnable.t.sol#L88
[test_givenDisabled_whenUnauthorizedCallerReEnables_reverts]: ./reEnable.t.sol#L116
[test_givenBurnerLoansPolicyInactive_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L139
[test_givenGraceExpired_whenPermittedCallerReEnables_reverts]: ./reEnable.t.sol#L165
[test_givenGraceExpiredAndTargetInactive_revertsBeforeTargetValidation]: ./reEnable.t.sol#L193

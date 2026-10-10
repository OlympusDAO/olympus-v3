# BurnerLoansYieldClaimer.setGracePeriod coverage plan

Scope: re-enable grace-period setter and getter.

Only the admin may update the value, and only while the claimer is locally enabled. Kernel activity
does not gate the setter. Validation order is enabled state, admin authorization, then the nonzero
period requirement. Every successful call emits `GracePeriodSet`, including a same-value call.

## Scenarios

| ID | Caller | Claimer Kernel/local state | Input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-GRACE-L01 | Any caller | Fuzz active/inactive; disabled | Fuzz `uint32`, including zero | `NotEnabled()` before authorization or numeric validation | Unchanged | Covered: [test][test_givenDisabled_revertsBeforeAuthorizationOrValidation] |
| BLYC-GRACE-A01 | Any non-admin, fuzz | Fuzz active/inactive; enabled | Fuzz `uint32`, including zero | `ROLES_RequireRole(ADMIN)` before numeric validation | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts] |
| BLYC-GRACE-I01 | Admin | Fuzz active/inactive; enabled | 0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test][test_givenZeroPeriod_reverts] |
| BLYC-GRACE-P01 | Admin | Fuzz active/inactive; enabled | Fuzz 1..`uint32.max`; seed 1 and max; exclude current | Success | Exact value stored; one exact `GracePeriodSet`; other configuration and cursor unchanged | Covered: [fuzz][test_givenDifferentValidPeriod_setsPeriod], [boundaries][test_whenGracePeriodBoundaryUsed_storesExactPeriod] |
| BLYC-GRACE-P02 | Admin | Fuzz active/inactive; enabled | Current period | Success | Value remains the same; one exact `GracePeriodSet` is still emitted | Covered: [test][test_givenCurrentPeriod_emitsEvent] |

[test_givenDisabled_revertsBeforeAuthorizationOrValidation]: ./setGracePeriod.t.sol#L16
[test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts]: ./setGracePeriod.t.sol#L32
[test_givenZeroPeriod_reverts]: ./setGracePeriod.t.sol#L49
[test_givenDifferentValidPeriod_setsPeriod]: ./setGracePeriod.t.sol#L61
[test_whenGracePeriodBoundaryUsed_storesExactPeriod]: ./setGracePeriod.t.sol#L88
[test_givenCurrentPeriod_emitsEvent]: ./setGracePeriod.t.sol#L104

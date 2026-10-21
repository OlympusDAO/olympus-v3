# BurnerLoansYieldClaimer.setMinimumGasToAttempt coverage plan

Scope: attempt-threshold setter and getter.

## Domains and assertions

`admin` and `burner_loans_admin` are independently permitted. Local disablement and Kernel policy
membership do not gate this configuration surface. Authorization precedes numeric validation. The
input is valid only when it strictly exceeds the current `gasReserve`. A changed valid value is
stored and emits `MinimumGasToAttemptSet`; a valid same-value call is a no-op.

Unchanged means all gas settings, cursor, target state, and lifecycle state retain their pre-call
values; no event is committed.

| ID | Caller | Task Kernel/local state | Current reserve | Input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MIN-A01 | Any caller outside both permitted classes, fuzz | Fuzz active/inactive and enabled/disabled | Valid | Fuzz `uint32` | `NotAuthorised()` before input validation | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsMinimumGas_reverts] |
| MIN-I01 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz valid | Fuzz 0..reserve; seed 0, 1, reserve | `BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt()` | Unchanged | Covered: [range][test_whenMinimumGasDoesNotExceedReserve_reverts], [boundaries][test_whenMinimumGasBoundaryIsInvalid_reverts] |
| MIN-P01 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz valid | Fuzz reserve+1..`uint32.max`, excluding current; seed reserve+1 and max | Success | Exact value stored; one exact event; other settings/cursor unchanged | Covered: [range][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [boundaries][test_whenMinimumGasBoundariesSet_updatesValue] |
| MIN-P02 | Each permitted class | Fuzz active/inactive and enabled/disabled | Valid | Current threshold | Success | No storage change or event | Covered: [test][test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp] |

[test_whenUnauthorizedCallerSetsMinimumGas_reverts]: ./setMinimumGasToAttempt.t.sol#L11
[test_whenMinimumGasDoesNotExceedReserve_reverts]: ./setMinimumGasToAttempt.t.sol#L30
[test_whenPermittedCallerSetsValidMinimumGas_updatesValue]: ./setMinimumGasToAttempt.t.sol#L79
[test_whenMinimumGasBoundariesSet_updatesValue]: ./setMinimumGasToAttempt.t.sol#L106
[test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp]: ./setMinimumGasToAttempt.t.sol#L120
[test_whenMinimumGasBoundaryIsInvalid_reverts]: ./setMinimumGasToAttempt.t.sol#L51

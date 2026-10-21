# BurnerLoansYieldClaimer.setGasReserve coverage plan

Scope: cleanup-reserve setter and getter.

## Domains and assertions

`admin` and `burner_loans_admin` are independently permitted. Local disablement and Kernel policy
membership do not gate this configuration surface. Authorization precedes numeric validation. The
input must be at least the implementation minimum of 100,000 gas and strictly below the current
`minimumGasToAttempt`. A changed valid value is stored and emits `GasReserveSet`; a valid same-value
call is a no-op.

Unchanged means all gas settings, cursor, target state, and lifecycle state retain their pre-call
values; no event is committed.

| ID | Caller | Task Kernel/local state | Current threshold | Input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RES-A01 | Any caller outside both permitted classes, fuzz | Fuzz active/inactive and enabled/disabled | Valid | Fuzz `uint32` | `NotAuthorised()` before input validation | Unchanged | Covered: [test][test_whenUnauthorizedCallerSetsReserve_reverts] |
| RES-I01 | Each permitted class | Fuzz active/inactive and enabled/disabled | Valid | Fuzz 0..99,999; seed 0 and 99,999 | `BurnerLoansYieldClaimer_InvalidGasReserve()` | Unchanged | Covered: [range][test_whenPermittedCallerSetsReserveBelowMinimum_reverts], [boundaries][test_whenReserveBoundaryIsInvalid_reverts] |
| RES-I02 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz valid | Fuzz threshold..`uint32.max`; seed threshold and max | Same error | Unchanged | Covered: [range][test_whenReserveReachesThreshold_reverts], [boundaries][test_whenReserveBoundaryIsInvalid_reverts] |
| RES-P01 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz 100,002..`uint32.max` | Fuzz 100,001..threshold-1, excluding current; seed 100,000 and threshold-1 | Success | Exact value stored; one exact event; other settings/cursor unchanged | Covered: [range][test_whenPermittedCallerSetsValidReserve_updatesValue], [boundaries][test_whenReserveBoundariesSet_updatesValue] |
| RES-P02 | Each permitted class | Fuzz active/inactive and enabled/disabled | Valid | Current reserve | Success | No storage change or event | Covered: [test][test_whenPermittedCallerSetsCurrentReserve_isNoOp] |

[test_whenUnauthorizedCallerSetsReserve_reverts]: ./setGasReserve.t.sol#L13
[test_whenPermittedCallerSetsReserveBelowMinimum_reverts]: ./setGasReserve.t.sol#L32
[test_whenReserveReachesThreshold_reverts]: ./setGasReserve.t.sol#L53
[test_whenPermittedCallerSetsValidReserve_updatesValue]: ./setGasReserve.t.sol#L100
[test_whenReserveBoundariesSet_updatesValue]: ./setGasReserve.t.sol#L127
[test_whenPermittedCallerSetsCurrentReserve_isNoOp]: ./setGasReserve.t.sol#L142
[test_whenReserveBoundaryIsInvalid_reverts]: ./setGasReserve.t.sol#L74

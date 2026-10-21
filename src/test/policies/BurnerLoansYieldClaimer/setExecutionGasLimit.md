# BurnerLoansYieldClaimer.setExecutionGasLimit coverage plan

Scope: complete-task gas-limit setter and getter.

Admin and Burner Loans admin are independently permitted. Local disablement and Kernel policy
membership do not gate the setter. Authorization precedes numeric validation. A changed permitted,
nonzero call stores the supplied value and emits `ExecutionGasLimitSet`; a valid same-value call is
an event-free no-op, matching `RevenueDistributorTask`.

## Scenarios

| ID | Caller | Claimer Kernel/local state | Input | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-GAS-A01 | Any caller outside both permitted classes, fuzz | Fuzz active/inactive and enabled/disabled | Fuzz `uint32`, including zero | `NotAuthorised()` before numeric validation | Unchanged | Covered: [test][test_givenUnauthorizedCaller_reverts] |
| BLYC-GAS-I01 | Each permitted class | Fuzz active/inactive and enabled/disabled | 0 | `BurnerLoansYieldClaimer_InvalidExecutionGasLimit()` | Unchanged | Covered: [test][test_givenZeroLimit_reverts] |
| BLYC-GAS-P01 | Admin | Fuzz active/inactive and enabled/disabled | Valid nonzero value different from current | Success | Exact value stored; one exact `ExecutionGasLimitSet`; other configuration and cursor unchanged | Covered: [test][test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration] |
| BLYC-GAS-P02 | Burner Loans admin | Fuzz active/inactive and enabled/disabled | Valid nonzero value different from current | Success | Same effects as P01 | Covered: [test][test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration] |
| BLYC-GAS-P03 | Each permitted class | Fuzz active/inactive and enabled/disabled | Fuzz 1..`uint32.max`; seed 1 and max; exclude current | Success | Same effects as P01 | Covered: [fuzz][test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration], [boundaries][test_whenExecutionGasLimitBoundaryUsed_storesExactLimit] |
| BLYC-GAS-P04 | Each permitted class | Fuzz active/inactive and enabled/disabled | Current limit | Success | No storage change or event | Covered: [test][test_whenPermittedCallerSetsCurrentLimit_isNoOp] |

[test_givenUnauthorizedCaller_reverts]: ./setExecutionGasLimit.t.sol#L11
[test_givenZeroLimit_reverts]: ./setExecutionGasLimit.t.sol#L30
[test_whenPermittedCallerSetsDifferentValidLimit_updatesConfiguration]: ./setExecutionGasLimit.t.sol#L44
[test_whenExecutionGasLimitBoundaryUsed_storesExactLimit]: ./setExecutionGasLimit.t.sol#L74
[test_whenPermittedCallerSetsCurrentLimit_isNoOp]: ./setExecutionGasLimit.t.sol#L92

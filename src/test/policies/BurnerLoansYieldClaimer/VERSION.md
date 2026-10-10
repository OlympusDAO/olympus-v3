# BurnerLoansYieldClaimer.VERSION coverage plan

Scope: version metadata.

## Scenarios

| ID | Caller | Task Kernel activity | Task local state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-VERSION-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero] |

[test_whenAnyCallerReadsVersion_returnsOneZero]: ./VERSION.t.sol#L8

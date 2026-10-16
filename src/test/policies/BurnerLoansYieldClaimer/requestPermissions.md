# BurnerLoansYieldClaimer.requestPermissions coverage plan

Scope: permission declaration.

## Scenarios

| ID | Caller | Task Kernel activity | Task local state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-PERMS-P01 | Any caller, fuzz | Fuzz active/inactive | Fuzz enabled/disabled | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty] |

[test_whenAnyCallerRequestsPermissions_returnsEmpty]: ./requestPermissions.t.sol#L10

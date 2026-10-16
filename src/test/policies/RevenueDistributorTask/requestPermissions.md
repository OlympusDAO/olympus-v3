# RevenueDistributorTask.requestPermissions scenario plan

Scope: permission declaration.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-PERMS-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty] |

[test_whenAnyCallerRequestsPermissions_returnsEmpty]: ./requestPermissions.t.sol#L9

# RevenueDistributorTask.requestPermissions scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: permission declaration.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-PERMS-P01 | Fuzz all callers | true | true | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty], [test][test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds] |
| RDTASK-PERMS-P02 | Fuzz all callers | true | false | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty], [test][test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds] |
| RDTASK-PERMS-P03 | Fuzz all callers | false | true | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty], [test][test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds] |
| RDTASK-PERMS-P04 | Fuzz all callers | false | false | Returns an empty permission array | Read only | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty], [test][test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds] |

[test_whenAnyCallerRequestsPermissions_returnsEmpty]: ./requestPermissions.t.sol#L9

[test_whenAnyCallerRequestsPermissions_returnsEmptyLifecycleSeeds]: ./requestPermissions.t.sol#L30

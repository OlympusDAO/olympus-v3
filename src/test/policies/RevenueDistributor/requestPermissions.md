# RevenueDistributor.requestPermissions scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: permission declaration.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-PERMS-P01 | Fuzz all callers | true | true | Returns an empty permission array | Read only | Covered: [test][test_whenPermissionsRequested_returnsEmptyArray], [test][test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds] |
| RD-PERMS-P02 | Fuzz all callers | true | false | Returns an empty permission array | Read only | Covered: [test][test_whenPermissionsRequested_returnsEmptyArray], [test][test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds] |
| RD-PERMS-P03 | Fuzz all callers | false | true | Returns an empty permission array | Read only | Covered: [test][test_whenPermissionsRequested_returnsEmptyArray], [test][test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds] |
| RD-PERMS-P04 | Fuzz all callers | false | false | Returns an empty permission array | Read only | Covered: [test][test_whenPermissionsRequested_returnsEmptyArray], [test][test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds] |

[test_whenPermissionsRequested_returnsEmptyArray]: ./requestPermissions.t.sol#L9

[test_whenPermissionsRequested_returnsEmptyArrayLifecycleSeeds]: ./requestPermissions.t.sol#L30

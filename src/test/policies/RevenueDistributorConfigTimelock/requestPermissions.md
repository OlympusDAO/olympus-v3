# RevenueDistributorConfigTimelock.requestPermissions scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: permission declaration.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-PERMS-P01 | Fuzz all callers | true | true | Returns an empty permission array | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissions], [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds] |
| RDCT-PERMS-P02 | Fuzz all callers | true | false | Returns an empty permission array | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissions], [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds] |
| RDCT-PERMS-P03 | Fuzz all callers | false | true | Returns an empty permission array | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissions], [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds] |
| RDCT-PERMS-P04 | Fuzz all callers | false | false | Returns an empty permission array | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissions], [test][test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds] |

[test_whenCalledInAnyLifecycleState_returnsEmptyPermissions]: ./requestPermissions.t.sol#L11

[test_whenCalledInAnyLifecycleState_returnsEmptyPermissionsLifecycleSeeds]: ./requestPermissions.t.sol#L32

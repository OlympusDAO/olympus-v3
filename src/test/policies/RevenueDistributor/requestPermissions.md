# RevenueDistributor.requestPermissions scenario plan

Scope: permission declaration.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-PERMS-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns an empty permission array | Read only | Covered: [evidence][test_whenPermissionsRequested_returnsEmptyArray] |

[test_whenPermissionsRequested_returnsEmptyArray]: ./requestPermissions.t.sol#L9

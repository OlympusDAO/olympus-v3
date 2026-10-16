# RevenueDistributorConfigTimelock.requestPermissions scenario plan

Scope: permission declaration.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-PERMS-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns an empty permission array | Read only | Covered: [evidence][testFuzz_whenCalledInAnyLifecycleState_returnsEmptyPermissions] |

[testFuzz_whenCalledInAnyLifecycleState_returnsEmptyPermissions]: ./requestPermissions.t.sol

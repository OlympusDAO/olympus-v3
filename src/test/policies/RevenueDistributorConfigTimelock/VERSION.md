# RevenueDistributorConfigTimelock.VERSION scenario plan

Scope: version metadata.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-VERSION-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns `(1, 0)` | Read only | Covered: [evidence][testFuzz_whenCalledInAnyLifecycleState_returnsVersion] |

[testFuzz_whenCalledInAnyLifecycleState_returnsVersion]: ./VERSION.t.sol

# RevenueDistributorConfigTimelock.VERSION scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: version metadata.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-VERSION-P01 | Fuzz all callers | true | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsVersion], [test][test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds] |
| RDCT-VERSION-P02 | Fuzz all callers | true | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsVersion], [test][test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds] |
| RDCT-VERSION-P03 | Fuzz all callers | false | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsVersion], [test][test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds] |
| RDCT-VERSION-P04 | Fuzz all callers | false | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenCalledInAnyLifecycleState_returnsVersion], [test][test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds] |

[test_whenCalledInAnyLifecycleState_returnsVersion]: ./VERSION.t.sol#L8

[test_whenCalledInAnyLifecycleState_returnsVersionLifecycleSeeds]: ./VERSION.t.sol#L30

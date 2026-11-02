# RevenueDistributor.VERSION scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: version metadata.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RD-VERSION-P01 | Fuzz all callers | true | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenVersionRead_returnsVersionOneZero], [test][test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds] |
| RD-VERSION-P02 | Fuzz all callers | true | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenVersionRead_returnsVersionOneZero], [test][test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds] |
| RD-VERSION-P03 | Fuzz all callers | false | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenVersionRead_returnsVersionOneZero], [test][test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds] |
| RD-VERSION-P04 | Fuzz all callers | false | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenVersionRead_returnsVersionOneZero], [test][test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds] |

[test_whenVersionRead_returnsVersionOneZero]: ./VERSION.t.sol#L8

[test_whenVersionRead_returnsVersionOneZeroLifecycleSeeds]: ./VERSION.t.sol#L30

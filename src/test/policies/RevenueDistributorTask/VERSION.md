# RevenueDistributorTask.VERSION scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: version metadata.

## Scenarios

| ID | Caller | Local active | Local enabled | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-VERSION-P01 | Fuzz all callers | true | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero], [test][test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds] |
| RDTASK-VERSION-P02 | Fuzz all callers | true | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero], [test][test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds] |
| RDTASK-VERSION-P03 | Fuzz all callers | false | true | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero], [test][test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds] |
| RDTASK-VERSION-P04 | Fuzz all callers | false | false | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero], [test][test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds] |

[test_whenAnyCallerReadsVersion_returnsOneZero]: ./VERSION.t.sol#L8

[test_whenAnyCallerReadsVersion_returnsOneZeroLifecycleSeeds]: ./VERSION.t.sol#L30

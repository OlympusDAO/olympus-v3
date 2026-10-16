# RevenueDistributorTask.VERSION scenario plan

Scope: version metadata.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-VERSION-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns `(1, 0)` | Read only | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero] |

[test_whenAnyCallerReadsVersion_returnsOneZero]: ./VERSION.t.sol#L8

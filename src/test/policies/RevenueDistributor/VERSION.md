# RevenueDistributor.VERSION scenario plan

Scope: version metadata.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-VERSION-P01 | Any caller, fuzz | Policy active or inactive; locally enabled or disabled | Returns `(1, 0)` | Read only | Covered: [evidence][test_whenVersionRead_returnsVersionOneZero] |

[test_whenVersionRead_returnsVersionOneZero]: ./VERSION.t.sol#L8

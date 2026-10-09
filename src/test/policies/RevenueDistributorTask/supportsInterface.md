# RevenueDistributorTask.supportsInterface scenario plan

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-ERC165-P01 | Any caller, fuzz | Query one of IRevenueDistributorTask, IPeriodicTask, IVersioned, IERC165, IEnabler, IEnablerV2, IReEnabler or IGracePeriod | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P02 | Any caller, fuzz | Query `0xffffffff` | Returns false | Read only | Covered: [test][test_whenInvalidInterfaceQueried_returnsFalse] |
| RDTASK-ERC165-P03 | Any caller, fuzz | Query an unrelated interface ID | Returns false | Read only | Covered: [test][test_whenUnrelatedInterfaceQueried_returnsFalse] |

[test_whenSupportedInterfaceQueried_returnsTrue]: ./supportsInterface.t.sol#L17
[test_whenInvalidInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L41
[test_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L52

# RevenueDistributorTask.supportsInterface scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | interfaceId_ | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-ERC165-P01 | Fuzz all callers | type(IRevenueDistributorTask).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P04 | Fuzz all callers | type(IPeriodicTask).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P05 | Fuzz all callers | type(IVersioned).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P06 | Fuzz all callers | type(IERC165).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P07 | Fuzz all callers | type(IEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P08 | Fuzz all callers | type(IEnablerV2).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P09 | Fuzz all callers | type(IReEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P10 | Fuzz all callers | type(IGracePeriod).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDTASK-ERC165-P02 | Fuzz all callers | Query `0xffffffff` | Returns false | Read only | Covered: [test][test_whenInvalidInterfaceQueried_returnsFalse] |
| RDTASK-ERC165-P03 | Fuzz all callers | Query an unrelated interface ID | Returns false | Read only | Covered: [test][test_whenUnrelatedInterfaceQueried_returnsFalse] |

[test_whenSupportedInterfaceQueried_returnsTrue]: ./supportsInterface.t.sol#L17
[test_whenInvalidInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L42
[test_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L53

# RevenueDistributor.supportsInterface scenario plan

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-ERC165-P01 | Any caller, fuzz | Query one of IRevenueDistributor, IRevenueDistributorRescue, IConfigOperator, IVersioned, IERC165, IEnabler, IEnablerV2, IReEnabler or IGracePeriod | Returns true | Read only | Covered: [evidence][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P02 | Any caller, fuzz | Query `0xffffffff` | Returns false | Read only | Covered: [evidence][test_whenUnsupportedInterfaceQueried] |
| RD-ERC165-P03 | Any caller, fuzz | Query any other interface ID | Returns false | Read only | Covered: [evidence][test_whenUnrelatedInterfaceQueried_returnsFalse] |

[test_whenSupportedInterfaceQueried]: ./supportsInterface.t.sol#L21
[test_whenUnsupportedInterfaceQueried]: ./supportsInterface.t.sol#L47
[test_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L53

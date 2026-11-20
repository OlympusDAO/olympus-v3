# RevenueDistributor.supportsInterface scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | interfaceId_ | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-ERC165-P01 | Fuzz all callers | type(IRevenueDistributor).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P04 | Fuzz all callers | type(IRevenueDistributorRescue).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P05 | Fuzz all callers | type(IConfigOperator).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P06 | Fuzz all callers | type(IVersioned).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P07 | Fuzz all callers | type(IERC165).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P08 | Fuzz all callers | type(IEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P09 | Fuzz all callers | type(IEnablerV2).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P10 | Fuzz all callers | type(IReEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P11 | Fuzz all callers | type(IGracePeriod).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried] |
| RD-ERC165-P02 | Fuzz all callers | Query `0xffffffff` | Returns false | Read only | Covered: [evidence][test_whenUnsupportedInterfaceQueried] |
| RD-ERC165-P03 | Fuzz all callers | Query any other interface ID | Returns false | Read only | Covered: [test][test_whenUnrelatedInterfaceQueried_returnsFalse] |

[test_whenSupportedInterfaceQueried]: ./supportsInterface.t.sol#L21
[test_whenUnsupportedInterfaceQueried]: ./supportsInterface.t.sol#L67
[test_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L73

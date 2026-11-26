# RevenueDistributorConfigTimelock.supportsInterface scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | interfaceId_ | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-ERC165-P01 | Fuzz all callers | type(IRevenueDistributorConfigTimelock).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P04 | Fuzz all callers | type(ITimelockBatchQueue).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P05 | Fuzz all callers | type(IConfigTimelockBatchQueue).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P06 | Fuzz all callers | type(IVersioned).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P07 | Fuzz all callers | type(IERC165).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P08 | Fuzz all callers | type(IEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P09 | Fuzz all callers | type(IEnablerV2).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P10 | Fuzz all callers | type(IReEnabler).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P11 | Fuzz all callers | type(IGracePeriod).interfaceId | Returns true | Read only | Covered: [test][test_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P02 | Fuzz all callers | Query `0xffffffff` | Returns false | Read only | Covered: [evidence][test_whenInvalidInterfaceQueried_returnsFalse] |
| RDCT-ERC165-P03 | Fuzz all callers | Query an unrelated interface ID | Returns false | Read only | Covered: [test][test_whenUnrelatedInterfaceQueried_returnsFalse] |

[test_whenSupportedInterfaceQueried_returnsTrue]: ./supportsInterface.t.sol#L20
[test_whenInvalidInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L64
[test_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol#L70

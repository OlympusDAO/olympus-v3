# RevenueDistributorConfigTimelock.supportsInterface scenario plan

Scope: ERC-165 interface discovery.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-ERC165-P01 | Any caller, fuzz | Query one of IRevenueDistributorConfigTimelock, ITimelockBatchQueue, IConfigTimelockBatchQueue, IVersioned, IERC165, IEnabler, IEnablerV2, IReEnabler or IGracePeriod | Returns true | Read only | Covered: [evidence][testFuzz_whenSupportedInterfaceQueried_returnsTrue] |
| RDCT-ERC165-P02 | Any caller, fuzz | Query `0xffffffff` | Returns false | Read only | Covered: [evidence][testFuzz_whenInvalidInterfaceQueried_returnsFalse] |
| RDCT-ERC165-P03 | Any caller, fuzz | Query an unrelated interface ID | Returns false | Read only | Covered: [evidence][testFuzz_whenUnrelatedInterfaceQueried_returnsFalse] |

[testFuzz_whenSupportedInterfaceQueried_returnsTrue]: ./supportsInterface.t.sol
[testFuzz_whenInvalidInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol
[testFuzz_whenUnrelatedInterfaceQueried_returnsFalse]: ./supportsInterface.t.sol

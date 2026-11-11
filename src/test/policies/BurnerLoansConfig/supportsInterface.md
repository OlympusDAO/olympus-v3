# BurnerLoansConfig.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansConfig.sol#L897). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ERC165-P01 | Fuzz all callers | type(IBurnerLoansConfig).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenConfigInterfaceQueried] |
| BLCFG-ERC165-P02 | Fuzz all callers | type(IConfigOperator).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenOperatorInterfaceQueried] |
| BLCFG-ERC165-P03 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenVersionInterfaceQueried] |
| BLCFG-ERC165-P04 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenERC165InterfaceQueried] |
| BLCFG-ERC165-P05 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenEnablerInterfaceQueried] |
| BLCFG-ERC165-P06 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenEnablerV2InterfaceQueried] |
| BLCFG-ERC165-P07 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenReEnablerInterfaceQueried] |
| BLCFG-ERC165-P08 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenGraceInterfaceQueried] |
| BLCFG-ERC165-P12 | Fuzz all callers | type(IBurnerLoansCoreBound).interfaceId | true | Concrete Config exposes immutable core(); no service-interface inheritance or dependency reads | Covered: [test][test_whenCoreBindingInterfaceQueried] |
| BLCFG-ERC165-P09 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test][test_whenInvalidInterfaceQueried] |
| BLCFG-ERC165-P10 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test][test_whenZeroInterfaceQueried] |
| BLCFG-ERC165-P11 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test][test_whenUnknownInterfaceQueried] |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenConfigInterfaceQueried]: ./supportsInterface.t.sol#L20
[test_whenOperatorInterfaceQueried]: ./supportsInterface.t.sol#L30
[test_whenVersionInterfaceQueried]: ./supportsInterface.t.sol#L44
[test_whenERC165InterfaceQueried]: ./supportsInterface.t.sol#L54
[test_whenEnablerInterfaceQueried]: ./supportsInterface.t.sol#L64
[test_whenEnablerV2InterfaceQueried]: ./supportsInterface.t.sol#L74
[test_whenReEnablerInterfaceQueried]: ./supportsInterface.t.sol#L88
[test_whenGraceInterfaceQueried]: ./supportsInterface.t.sol#L102
[test_whenCoreBindingInterfaceQueried]: ./supportsInterface.t.sol#L112
[test_whenInvalidInterfaceQueried]: ./supportsInterface.t.sol#L126
[test_whenZeroInterfaceQueried]: ./supportsInterface.t.sol#L133
[test_whenUnknownInterfaceQueried]: ./supportsInterface.t.sol#L140

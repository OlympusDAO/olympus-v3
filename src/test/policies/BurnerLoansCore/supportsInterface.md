# BurnerLoansCore.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansCore.sol#L873). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-ERC165-P01 | Fuzz all callers | type(IBurnerLoansCore).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIBurnerLoansCoreQueried] |
| BLCORE-ERC165-P02 | Fuzz all callers | type(IOperatorAuth).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIOperatorAuthQueried] |
| BLCORE-ERC165-P03 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIVersionedQueried] |
| BLCORE-ERC165-P04 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIERC165Queried] |
| BLCORE-ERC165-P05 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIEnablerQueried] |
| BLCORE-ERC165-P06 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIEnablerV2Queried] |
| BLCORE-ERC165-P07 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIReEnablerQueried] |
| BLCORE-ERC165-P08 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test][test_whenIGracePeriodQueried] |
| BLCORE-ERC165-P09 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test][test_whenInvalidInterfaceQueried] |
| BLCORE-ERC165-P10 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test][test_whenZeroInterfaceQueried] |
| BLCORE-ERC165-P11 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test][test_whenOtherInterfaceQueried] |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_whenIBurnerLoansCoreQueried]: supportsInterface.t.sol#L19
[test_whenIERC165Queried]: supportsInterface.t.sol#L61
[test_whenIEnablerQueried]: supportsInterface.t.sol#L75
[test_whenIEnablerV2Queried]: supportsInterface.t.sol#L89
[test_whenIGracePeriodQueried]: supportsInterface.t.sol#L117
[test_whenIOperatorAuthQueried]: supportsInterface.t.sol#L33
[test_whenIReEnablerQueried]: supportsInterface.t.sol#L103
[test_whenIVersionedQueried]: supportsInterface.t.sol#L47
[test_whenInvalidInterfaceQueried]: supportsInterface.t.sol#L131
[test_whenOtherInterfaceQueried]: supportsInterface.t.sol#L145
[test_whenZeroInterfaceQueried]: supportsInterface.t.sol#L138

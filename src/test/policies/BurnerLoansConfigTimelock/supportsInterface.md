# BurnerLoansConfigTimelock.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L798). Coverage is recorded in the Test column.

Implementation: 12 scenario functions mapped; 12 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-ERC165-P01 | Fuzz all callers | type(IBurnerLoansConfigTimelock).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIBurnerLoansConfigTimelockQueried_thenSupported][test_givenAnyCaller_whenIBurnerLoansConfigTimelockQueried_thenSupported] |
| BLCT-ERC165-P02 | Fuzz all callers | type(IConfigTimelockBatchQueue).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIConfigTimelockBatchQueueQueried_thenSupported][test_givenAnyCaller_whenIConfigTimelockBatchQueueQueried_thenSupported] |
| BLCT-ERC165-P03 | Fuzz all callers | type(ITimelockBatchQueue).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenITimelockBatchQueueQueried_thenSupported][test_givenAnyCaller_whenITimelockBatchQueueQueried_thenSupported] |
| BLCT-ERC165-P04 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIVersionedQueried_thenSupported][test_givenAnyCaller_whenIVersionedQueried_thenSupported] |
| BLCT-ERC165-P05 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIERC165Queried_thenSupported][test_givenAnyCaller_whenIERC165Queried_thenSupported] |
| BLCT-ERC165-P06 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIEnablerQueried_thenSupported][test_givenAnyCaller_whenIEnablerQueried_thenSupported] |
| BLCT-ERC165-P07 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIEnablerV2Queried_thenSupported][test_givenAnyCaller_whenIEnablerV2Queried_thenSupported] |
| BLCT-ERC165-P08 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIReEnablerQueried_thenSupported][test_givenAnyCaller_whenIReEnablerQueried_thenSupported] |
| BLCT-ERC165-P09 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenIGracePeriodQueried_thenSupported][test_givenAnyCaller_whenIGracePeriodQueried_thenSupported] |
| BLCT-ERC165-P10 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenInvalidErc165InterfaceQueried_thenFalse][test_givenAnyCaller_whenInvalidErc165InterfaceQueried_thenFalse] |
| BLCT-ERC165-P11 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenZeroInterfaceQueried_thenFalse][test_givenAnyCaller_whenZeroInterfaceQueried_thenFalse] |
| BLCT-ERC165-P12 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Covered: [test_givenAnyCaller_whenUnknownInterfaceQueried_thenFalse][test_givenAnyCaller_whenUnknownInterfaceQueried_thenFalse] |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenAnyCaller_whenIBurnerLoansConfigTimelockQueried_thenSupported]: supportsInterface.t.sol#L20
[test_givenAnyCaller_whenIConfigTimelockBatchQueueQueried_thenSupported]: supportsInterface.t.sol#L36
[test_givenAnyCaller_whenITimelockBatchQueueQueried_thenSupported]: supportsInterface.t.sol#L52
[test_givenAnyCaller_whenIVersionedQueried_thenSupported]: supportsInterface.t.sol#L68
[test_givenAnyCaller_whenIERC165Queried_thenSupported]: supportsInterface.t.sol#L84
[test_givenAnyCaller_whenIEnablerQueried_thenSupported]: supportsInterface.t.sol#L100
[test_givenAnyCaller_whenIEnablerV2Queried_thenSupported]: supportsInterface.t.sol#L116
[test_givenAnyCaller_whenIReEnablerQueried_thenSupported]: supportsInterface.t.sol#L132
[test_givenAnyCaller_whenIGracePeriodQueried_thenSupported]: supportsInterface.t.sol#L148
[test_givenAnyCaller_whenInvalidErc165InterfaceQueried_thenFalse]: supportsInterface.t.sol#L164
[test_givenAnyCaller_whenZeroInterfaceQueried_thenFalse]: supportsInterface.t.sol#L172
[test_givenAnyCaller_whenUnknownInterfaceQueried_thenFalse]: supportsInterface.t.sol#L178

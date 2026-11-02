# BurnerLoansSeizerTask.supportsInterface coverage plan

Source: [supportsInterface](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L435). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-ERC165` identifies this contract/function.

Permissionless view, all lifecycle states; bytes4 input. Advertised interfaces derive from implementation and inherited bases, not union of every imported declaration interface.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Supported interfaces

| ID | Caller | interfaceId input | Return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ERC165-P01 | Fuzz all callers | type(IBurnerLoansSeizerTask).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P02 | Fuzz all callers | type(IPeriodicTask).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P03 | Fuzz all callers | type(IVersioned).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P04 | Fuzz all callers | type(IERC165).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P05 | Fuzz all callers | type(IEnabler).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P06 | Fuzz all callers | type(IEnablerV2).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P07 | Fuzz all callers | type(IReEnabler).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P08 | Fuzz all callers | type(IGracePeriod).interfaceId | true | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P09 | Fuzz all callers | 0xffffffff | false | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P10 | Fuzz all callers | 0x00000000 | false | No state, token, event or dependency changes | Unmapped |
| BLSEIZ-ERC165-P11 | Fuzz all callers | Fuzz bytes4 excluding the complete supported set listed above, zero and 0xffffffff | false | No state, token, event or dependency changes | Unmapped |

## Shared assertions

Compile the exact IDs listed above. Imported interfaces do not add advertised support.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Test organization

[supportsInterface.t.sol](./supportsInterface.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

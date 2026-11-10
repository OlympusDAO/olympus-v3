# BurnerLoansDebt.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L213). Implemented and mapped to the focused Foundry suite.

## Domains and notation

Scenario scope: `BLDEBT-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLDEBT-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test_whenVersionRead_thenConstant][test_whenVersionRead_thenConstant], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |

## Shared assertions

No VERSION API on four public action contracts.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenReadAcrossAllLifecycleStates_thenStable]: VERSION.t.sol#L27
[test_whenVersionRead_thenConstant]: VERSION.t.sol#L13

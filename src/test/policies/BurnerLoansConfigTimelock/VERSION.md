# BurnerLoansConfigTimelock.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L735). Coverage is recorded in the Test column.

Implementation: 1 scenario functions mapped; 1 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test_givenAnyCaller_whenVersionRead_thenOneZero][test_givenAnyCaller_whenVersionRead_thenOneZero] |

## Shared assertions

No VERSION API on four public action contracts.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenAnyCaller_whenVersionRead_thenOneZero]: VERSION.t.sol#L9

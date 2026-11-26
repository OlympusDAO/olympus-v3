# BurnerLoansYieldClaimerTask.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L137). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test][test_whenAnyCallerReadsVersion_returnsOneZero] |

## Shared assertions

No VERSION API on four public action contracts.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenAnyCallerReadsVersion_returnsOneZero]: VERSION.t.sol#L9

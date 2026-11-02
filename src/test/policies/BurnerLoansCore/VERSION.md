# BurnerLoansCore.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansCore.sol#L865). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCORE-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test][test_whenVersionQueried] |

## Shared assertions

No VERSION API on four public action contracts.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_whenVersionQueried]: VERSION.t.sol#L9

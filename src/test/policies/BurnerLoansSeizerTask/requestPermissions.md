# BurnerLoansSeizerTask.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L129). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: empty list.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Unmapped |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

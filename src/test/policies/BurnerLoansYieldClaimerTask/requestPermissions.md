# BurnerLoansYieldClaimerTask.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L126). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: empty list.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test][test_whenAnyCallerRequestsPermissions_returnsEmpty] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_whenAnyCallerRequestsPermissions_returnsEmpty]: requestPermissions.t.sol#L10

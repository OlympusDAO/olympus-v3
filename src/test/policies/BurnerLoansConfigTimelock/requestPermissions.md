# BurnerLoansConfigTimelock.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansConfigTimelock.sol#L142). Coverage is recorded in the Test column.

Implementation: 1 scenario functions mapped; 1 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: empty list.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test_givenEachLifecycleState_whenPermissionsRead_thenEmpty][test_givenEachLifecycleState_whenPermissionsRead_thenEmpty] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenEachLifecycleState_whenPermissionsRead_thenEmpty]: requestPermissions.t.sol#L11

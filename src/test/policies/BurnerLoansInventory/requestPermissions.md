# BurnerLoansInventory.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/BurnerLoansInventory.sol#L164). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: MINTR mintOhm,burnOhm,increaseMintApproval,decreaseMintApproval.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenLifecycle_whenReadByAnyCaller]: requestPermissions.t.sol#L39
[test_whenReadLifecycleSeeds]: requestPermissions.t.sol#L58

# BurnerLoansInventory.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/BurnerLoansInventory.sol#L497). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test_givenLifecycle_whenReadByAnyCaller][test_givenLifecycle_whenReadByAnyCaller]; [test_whenReadLifecycleSeeds][test_whenReadLifecycleSeeds] |

## Shared assertions

No VERSION API on four public action contracts.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenLifecycle_whenReadByAnyCaller]: VERSION.t.sol#L14
[test_whenReadLifecycleSeeds]: VERSION.t.sol#L37

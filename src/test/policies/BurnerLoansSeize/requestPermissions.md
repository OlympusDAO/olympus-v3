# BurnerLoansSeize.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L132). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope: `BLLIQ-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: empty list.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Exact ordered keycode/selector pairs and length | Covered: [test_whenPermissionsRequested_thenEmpty][test_whenPermissionsRequested_thenEmpty], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable], [test_givenNeverActivated_whenPermissionsRequested_thenEmpty][test_givenNeverActivated_whenPermissionsRequested_thenEmpty], [test_givenKernelMigrated_whenPermissionsRequested_thenEmpty][test_givenKernelMigrated_whenPermissionsRequested_thenEmpty] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenKernelMigrated_whenPermissionsRequested_thenEmpty]: requestPermissions.t.sol#L54
[test_givenNeverActivated_whenPermissionsRequested_thenEmpty]: requestPermissions.t.sol#L42
[test_whenPermissionsRequested_thenEmpty]: requestPermissions.t.sol#L14
[test_whenReadAcrossAllLifecycleStates_thenStable]: requestPermissions.t.sol#L27

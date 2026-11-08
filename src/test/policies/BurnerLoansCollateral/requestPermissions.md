# BurnerLoansCollateral.requestPermissions coverage plan

Source: [requestPermissions](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L132). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-PERMISSIONS` identifies this contract/function.

Permissionless pure, no lifecycle or dependency admission. Exact ordered result: empty list.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No extras, duplicates or mutation.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOL-PERMISSIONS-P01 | Fuzz all callers | Before/after activation,disable,migration | Empty Permissions[]; length=0 | Covered: [test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable][test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable], [test_whenPermissionsRequested_thenEmpty][test_whenPermissionsRequested_thenEmpty], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable] |

## Shared assertions

No pricing/custody/configuration permissions added to public actions.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable]: changeKernel.t.sol#L59
[test_whenPermissionsRequested_thenEmpty]: requestPermissions.t.sol#L13
[test_whenReadAcrossAllLifecycleStates_thenStable]: requestPermissions.t.sol#L26

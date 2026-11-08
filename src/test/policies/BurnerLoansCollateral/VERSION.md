# BurnerLoansCollateral.VERSION coverage plan

Source: [VERSION](../../../policies/burnerloans/abstracts/BaseBurnerLoansAction.sol#L208). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-VERSION` identifies this contract/function.

Permissionless pure; lifecycle and callers irrelevant.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

Fixed for this table: Accounting / events: No effects.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOL-VERSION-P01 | Fuzz all callers | Any reachable state | Return(1,0) | Covered: [test_whenVersionRead_thenConstant][test_whenVersionRead_thenConstant], [test_whenReadAcrossAllLifecycleStates_thenStable][test_whenReadAcrossAllLifecycleStates_thenStable], [test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable][test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable] |

## Shared assertions

No VERSION API on four public action contracts.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable]: changeKernel.t.sol#L59
[test_whenReadAcrossAllLifecycleStates_thenStable]: VERSION.t.sol#L26
[test_whenVersionRead_thenConstant]: VERSION.t.sol#L12

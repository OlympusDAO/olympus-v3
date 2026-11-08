# BurnerLoansCollateral.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Covered: [test_givenNewKernel_whenPointerChanged_thenMembershipMustBeEstablished][test_givenNewKernel_whenPointerChanged_thenMembershipMustBeEstablished], [test_givenNewKernel_whenActionEnabled_thenCoreBindingMustAgree][test_givenNewKernel_whenActionEnabled_thenCoreBindingMustAgree], [test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable][test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable], [test_whenKernelChanges_thenOnlyPointerChanges][test_whenKernelChanges_thenOnlyPointerChanges], [test_whenKernelIsZeroSameOrDistinct_thenOnlyPointerChanges][test_whenKernelIsZeroSameOrDistinct_thenOnlyPointerChanges] |
| BLCOL-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Covered: [test_whenNonKernelChangesKernel_reverts][test_whenNonKernelChangesKernel_reverts] |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenNewKernel_whenActionEnabled_thenCoreBindingMustAgree]: changeKernel.t.sol#L44
[test_givenNewKernel_whenPointerChanged_thenMembershipMustBeEstablished]: changeKernel.t.sol#L20
[test_givenZeroKernel_whenPointerChanged_thenPureViewsRemainAvailable]: changeKernel.t.sol#L59
[test_whenKernelChanges_thenOnlyPointerChanges]: changeKernel.t.sol#L96
[test_whenKernelIsZeroSameOrDistinct_thenOnlyPointerChanges]: changeKernel.t.sol#L135
[test_whenNonKernelChangesKernel_reverts]: changeKernel.t.sol#L116

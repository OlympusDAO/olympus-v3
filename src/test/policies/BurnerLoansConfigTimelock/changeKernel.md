# BurnerLoansConfigTimelock.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage is recorded in the Test column.

Implementation: 2 scenario functions mapped; 2 Covered, 0 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Covered: [test_givenCurrentKernel_whenPointerChangedAcrossLifecycle_thenOnlyPointerChanges][test_givenCurrentKernel_whenPointerChangedAcrossLifecycle_thenOnlyPointerChanges] |
| BLCT-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Covered: [test_givenCallerNotCurrentKernel_whenPointerChanged_reverts][test_givenCallerNotCurrentKernel_whenPointerChanged_reverts] |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

[test_givenCurrentKernel_whenPointerChangedAcrossLifecycle_thenOnlyPointerChanges]: changeKernel.t.sol#L10
[test_givenCallerNotCurrentKernel_whenPointerChanged_reverts]: changeKernel.t.sol#L31

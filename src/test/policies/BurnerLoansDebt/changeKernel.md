# BurnerLoansDebt.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Implemented and mapped to the focused Foundry suite.

## Domains and notation

Scenario scope: `BLDEBT-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Covered: [test_whenKernelChanges_thenOnlyPointerChanges][test_whenKernelChanges_thenOnlyPointerChanges], [test_whenKernelIsZero_thenPointerChanges][test_whenKernelIsZero_thenPointerChanges], [test_whenKernelIsUnchanged_thenPointerStillAccepted][test_whenKernelIsUnchanged_thenPointerStillAccepted] |
| BLDEBT-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Covered: [test_whenNonKernelChangesKernel_reverts][test_whenNonKernelChangesKernel_reverts] |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Existing tests informing this plan

New modular entrypoint with no direct legacy counterpart. Its caller/binding/replacement cases supplement the existing settlement and lifecycle suites; do not manufacture a legacy coverage mapping.

[test_whenKernelChanges_thenOnlyPointerChanges]: changeKernel.t.sol#L10
[test_whenKernelIsUnchanged_thenPointerStillAccepted]: changeKernel.t.sol#L44
[test_whenKernelIsZero_thenPointerChanges]: changeKernel.t.sol#L39
[test_whenNonKernelChangesKernel_reverts]: changeKernel.t.sol#L27

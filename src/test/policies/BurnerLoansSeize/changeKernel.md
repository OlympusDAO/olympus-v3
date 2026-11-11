# BurnerLoansSeize.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope: `BLLIQ-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Covered: [test_whenKernelChanges_thenOnlyPointerChanges][test_whenKernelChanges_thenOnlyPointerChanges], [test_whenKernelIsZero_thenPointerChanges][test_whenKernelIsZero_thenPointerChanges], [test_whenKernelIsUnchanged_thenPointerStillAccepted][test_whenKernelIsUnchanged_thenPointerStillAccepted], [test_givenMigrationToFreshKernel_whenSeized_thenAdmissionUsesNewMembership][test_givenMigrationToFreshKernel_whenSeized_thenAdmissionUsesNewMembership] |
| BLLIQ-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Covered: [test_whenNonKernelChangesKernel_reverts][test_whenNonKernelChangesKernel_reverts] |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Existing tests informing this plan

New modular entrypoint with no direct legacy counterpart. Its caller/binding/replacement cases supplement the existing settlement and lifecycle suites; do not manufacture a legacy coverage mapping.

[test_givenMigrationToFreshKernel_whenSeized_thenAdmissionUsesNewMembership]: changeKernel.t.sol#L59
[test_whenKernelChanges_thenOnlyPointerChanges]: changeKernel.t.sol#L16
[test_whenKernelIsUnchanged_thenPointerStillAccepted]: changeKernel.t.sol#L54
[test_whenKernelIsZero_thenPointerChanges]: changeKernel.t.sol#L49
[test_whenNonKernelChangesKernel_reverts]: changeKernel.t.sol#L33

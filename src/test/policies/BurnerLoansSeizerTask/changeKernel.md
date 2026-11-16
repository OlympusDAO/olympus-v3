# BurnerLoansSeizerTask.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-KERNEL-P01 | Current Kernel | New pointer equals current Kernel; enabled/disabled independently | Success, including same-pointer assignment | Only kernel pointer may be written; no task event or reconfiguration | Unmapped |
| BLSEIZ-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Unmapped |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [x] Review concrete branches and inherited guard order.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

## Migration and co-located activity reads

The framework trusts the destination supplied by the current Kernel; this function does not probe its code or lifecycle. No ADMIN/HEART grant substitutes for current-Kernel identity.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-KERNEL-P03 | Current Kernel | Distinct nonzero destination, including EOA and MAX160; local state true/false | Store destination exactly; retain ROLES, assets, cursors, limits and transition fields | Unmapped |
| BLSEIZ-KERNEL-P04 | Current Kernel | Destination zero | Store zero without validation; retain every other field; subsequent Kernel-dependent reads fail | Unmapped |
| BLSEIZ-KERNEL-A01 | Old Kernel after migration | Distinct new Kernel is now stored | KernelAdapter_OnlyKernel(oldKernel); new Kernel alone can migrate again | Unmapped |
| BLSEIZ-KERNEL-V01 | Fuzz all callers | isActive(): current Kernel reports membership false/true independently of local enabled | Return authoritative current-Kernel membership; cached old membership does not determine result | Unmapped |
| BLSEIZ-KERNEL-T01 | Fuzz all callers | isActive(): current Kernel lookup reverts | Propagate exact dependency error; no state changes | Unmapped |

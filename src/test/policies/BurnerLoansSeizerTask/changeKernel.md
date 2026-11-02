# BurnerLoansSeizerTask.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Unmapped |
| BLSEIZ-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Unmapped |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

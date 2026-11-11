# BurnerLoansCore.changeKernel coverage plan

Source: [changeKernel](../../../Kernel.sol#L91). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-KERNEL` identifies this contract/function.

Inherited KernelAdapter onlyKernel. New pointer is trusted Kernel migration input; no same-Core/zero validation in changeKernel itself.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-KERNEL-P01 | Current Kernel | Same/distinct/zero new Kernel across lifecycle | Pointer updates without other checks | Only kernel pointer changes; no role/module/Core rebinding | Covered: [test][test_givenCurrentKernel_whenChanged], [test][test_whenKernelBoundarySeeds], [test][test_givenNewKernel_whenChanged_thenMembershipIsIndependent] |
| BLCORE-KERNEL-P02 | Fuzz except current Kernel | Any new pointer including same/zero | KernelAdapter_OnlyKernel(caller) | Unchanged | Covered: [test][test_givenOtherCaller_whenChanged_reverts] |
| BLCORE-KERNEL-D01 | Current Kernel executor then ADMIN/account | Actual MigrateKernel; reinstall modules and activate Core; select new Auth bound to new Kernel | Old Auth rejects foreign Kernel despite retained old membership; new Auth accepts/captures/validates grant; retired cancellation succeeds | Epoch +1; custody/positions unchanged; old cancellation does not affect new Auth | Covered: [migration][test_givenKernelMigration_whenAuthReplaced_newKernelAdmitsGrants] |

## Shared assertions

After migration test Kernel.isPolicyActive independently and action enable/Core admission mismatch checks; new Kernel governance must reactivate/reconfigure graph. Zero pointer breaks later Kernel reads; setter itself succeeds as legacy framework tests demonstrate.

Co-located API assertions: `kernel`, `isActive`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Existing tests informing this plan

No dedicated same-name legacy suite exists. Use related custody, arithmetic and lifecycle regression families in the suite index; this API needs new direct tests.

[test_givenCurrentKernel_whenChanged]: changeKernel.t.sol#L97
[test_givenNewKernel_whenChanged_thenMembershipIsIndependent]: changeKernel.t.sol#L138
[test_givenOtherCaller_whenChanged_reverts]: changeKernel.t.sol#L117
[test_whenKernelBoundarySeeds]: changeKernel.t.sol#L132

[test_givenKernelMigration_whenAuthReplaced_newKernelAdmitsGrants]: ./changeKernel.t.sol#L23

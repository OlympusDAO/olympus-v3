# RevenueDistributorTask.changeKernel scenario plan

Scope: inherited Kernel pointer replacement and its `kernel`/`isActive` getters.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDTASK-KERNEL-A01 | Any caller except current Kernel, fuzz | Any policy state; any new pointer | KernelAdapter_OnlyKernel(caller) | Kernel pointer and dependencies unchanged | Covered: [test][test_whenCallerIsNotCurrentKernel_reverts] |
| RDTASK-KERNEL-P01 | Current Kernel | New pointer is distinct and nonzero | Success | `kernel` changes; dependencies do not refresh implicitly; `isActive` follows the new Kernel; immutable distributor is unchanged | Covered: [test][test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly] |
| RDTASK-KERNEL-P02 | Current Kernel | New pointer equals current Kernel | Success | Pointer and distributor unchanged; no dependency refresh | Covered: [test][test_whenCurrentKernelChangesToSameKernel_succeeds] |
| RDTASK-KERNEL-P03 | Current Kernel | New pointer is address(0) | Success | Pointer becomes zero; distributor unchanged; no dependency refresh | Covered: [test][test_whenCurrentKernelChangesToZero_preservesOtherState] |

[test_whenCallerIsNotCurrentKernel_reverts]: ./changeKernel.t.sol#L9
[test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly]: ./changeKernel.t.sol#L31
[test_whenCurrentKernelChangesToSameKernel_succeeds]: ./changeKernel.t.sol#L45
[test_whenCurrentKernelChangesToZero_preservesOtherState]: ./changeKernel.t.sol#L57

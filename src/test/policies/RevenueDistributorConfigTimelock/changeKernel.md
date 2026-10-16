# RevenueDistributorConfigTimelock.changeKernel scenario plan

Scope: inherited Kernel pointer replacement and its `kernel`/`isActive` getters.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-KERNEL-A01 | Any caller except current Kernel, fuzz | Any policy state; any new pointer | KernelAdapter_OnlyKernel(caller) | Kernel pointer and dependencies unchanged | Covered: [evidence][testFuzz_whenNonKernelChangesKernel_reverts] |
| RDCT-KERNEL-P01 | Current Kernel | New pointer is distinct and nonzero | Success | `kernel` changes; dependencies do not refresh implicitly; `isActive` follows the new Kernel | Covered: [evidence][test_whenKernelChangesToDistinctKernel_updatesOnlyPointer] |
| RDCT-KERNEL-P02 | Current Kernel | New pointer equals current Kernel | Success | Pointer unchanged; no dependency refresh | Covered: [evidence][test_whenKernelChangesToSameKernel_preservesDependencies] |
| RDCT-KERNEL-P03 | Current Kernel | New pointer is address(0) | Success | Pointer becomes zero; no dependency refresh | Covered: [evidence][test_whenKernelChangesToZero_setsZeroPointer] |

[testFuzz_whenNonKernelChangesKernel_reverts]: ./changeKernel.t.sol
[test_whenKernelChangesToDistinctKernel_updatesOnlyPointer]: ./changeKernel.t.sol#L26
[test_whenKernelChangesToSameKernel_preservesDependencies]: ./changeKernel.t.sol#L38
[test_whenKernelChangesToZero_setsZeroPointer]: ./changeKernel.t.sol#L51

# BurnerLoansYieldClaimer.changeKernel coverage plan

Scope: inherited Kernel pointer replacement and co-located `kernel`/`isActive` assertions.

Only the current Kernel may call this function. It accepts any replacement pointer, including the
current Kernel or zero, and does not refresh ROLES or change the immutable Burner Loans target.

## Scenarios

| ID | Caller | New Kernel pointer | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-KERNEL-A01 | Any caller except current Kernel, fuzz | Fuzz address | `KernelAdapter_OnlyKernel(caller)` | Kernel pointer, ROLES cache, target and configuration unchanged | Covered: [test][test_whenCallerIsNotCurrentKernel_reverts] |
| BLYC-KERNEL-P01 | Current Kernel | Distinct nonzero Kernel | Success | Kernel pointer changes; task is inactive in new Kernel; no dependency refresh; target/configuration unchanged | Covered: [test][test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly] |
| BLYC-KERNEL-P02 | Current Kernel | Current Kernel | Success | Pointer and all other state unchanged | Covered: [test][test_whenCurrentKernelChangesToSameKernel_succeeds] |
| BLYC-KERNEL-P03 | Current Kernel | Zero | Success | Pointer becomes zero; no dependency refresh; target/configuration unchanged | Covered: [test][test_whenCurrentKernelChangesToZero_preservesOtherState] |

[test_whenCallerIsNotCurrentKernel_reverts]: ./changeKernel.t.sol#L10
[test_whenCurrentKernelChangesToDistinctKernel_updatesPointerOnly]: ./changeKernel.t.sol#L33
[test_whenCurrentKernelChangesToSameKernel_succeeds]: ./changeKernel.t.sol#L49
[test_whenCurrentKernelChangesToZero_preservesOtherState]: ./changeKernel.t.sol#L61

# BurnerLoansYieldClaimer constructor coverage plan

Scope: deployment, immutable Burner Loans binding, and directly initialized getters.

The target must advertise `IBurnerLoansYieldClaim`, `IBurnerLoansView`, and `IEnabler`, and report
the constructor Kernel. This single compatibility error also covers the zero address. Construction
does not require either policy to be Kernel-active or the target to be locally enabled. The
execution limit is stored exactly when nonzero. Successful deployment starts locally disabled with
cursor zero, a 250,000-gas attempt threshold, a 100,000-gas cleanup reserve, and the configured
Burner Loans re-enable grace period.

## Scenarios

| ID | Target address/code | Yield-claim interface | Asset-view interface | Lifecycle interface | Reported Kernel | `executionGasLimit_` | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-CTOR-P01 | Nonzero contract | Supported | Supported | Supported | Constructor Kernel | Fuzz 1..`uint32.max`; seed 1 and max | Deployment succeeds | Exact target/limit and defaults stored; four exact configuration events; task disabled | Covered: [fuzz][test_givenValidConfiguration_whenDeployed], [boundaries][test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit] |
| BLYC-CTOR-I01 | Zero | Unsupported | Unsupported | Unsupported | N/A | Valid nonzero | `BurnerLoansYieldClaimer_InvalidBurnerLoans(0)` | No policy deployed | Covered: [test][test_givenBurnerLoansIsZero_reverts] |
| BLYC-CTOR-I02 | EOA | Unsupported | Unsupported | Unsupported | N/A | Valid nonzero | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | No policy deployed | Covered: [test][test_givenBurnerLoansIsEoa_reverts] |
| BLYC-CTOR-I03 | Nonzero contract | Unsupported | Supported | Supported | Any | Valid nonzero | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | No policy deployed | Covered: [test][test_givenBurnerLoansDoesNotSupportYieldClaim_reverts] |
| BLYC-CTOR-I04 | Nonzero contract | Supported | Unsupported | Supported | Constructor Kernel | Valid nonzero | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | No policy deployed | Covered: [test][test_givenBurnerLoansDoesNotSupportAssetView_reverts] |
| BLYC-CTOR-I05 | Nonzero contract | Supported | Supported | Supported | Different Kernel | Valid nonzero | `BurnerLoansYieldClaimer_KernelMismatch(expected, actual)` | No policy deployed | Covered: [test][test_givenBurnerLoansUsesDifferentKernel_reverts] |
| BLYC-CTOR-I06 | Nonzero contract | Supported | Supported | Supported | Constructor Kernel | 0 | `BurnerLoansYieldClaimer_InvalidExecutionGasLimit()` | No policy deployed | Covered: [test][test_givenExecutionGasLimitIsZero_reverts] |
| BLYC-CTOR-I07 | Nonzero contract | Supported | Supported | Unsupported | Constructor Kernel | Valid nonzero | `BurnerLoansYieldClaimer_InvalidBurnerLoans(target)` | No policy deployed | Covered: [test][test_givenBurnerLoansDoesNotSupportLifecycle_reverts] |

[test_givenBurnerLoansIsZero_reverts]: ./constructor.t.sol#L23
[test_givenBurnerLoansDoesNotSupportYieldClaim_reverts]: ./constructor.t.sol#L34
[test_givenBurnerLoansDoesNotSupportAssetView_reverts]: ./constructor.t.sol#L47
[test_givenBurnerLoansDoesNotSupportLifecycle_reverts]: ./constructor.t.sol#L60
[test_givenBurnerLoansUsesDifferentKernel_reverts]: ./constructor.t.sol#L73
[test_givenExecutionGasLimitIsZero_reverts]: ./constructor.t.sol#L90
[test_givenValidConfiguration_whenDeployed]: ./constructor.t.sol#L98
[test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit]: ./constructor.t.sol#L140
[test_givenBurnerLoansIsEoa_reverts]: ./constructor.t.sol#L153

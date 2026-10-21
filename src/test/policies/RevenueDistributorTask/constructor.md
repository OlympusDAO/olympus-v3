# RevenueDistributorTask constructor scenario plan

Scope: constructor deployment and directly initialized getters.

The distributor must advertise both `IRevenueDistributor` and `IEnabler`. Construction does not
require the distributor to be locally enabled; `enable` and `reEnable` own that live-state check.
A zero distributor gives `RevenueDistributorTask_InvalidDistributor(address(0))`; the constructor
also requires `IEnabler` compatibility.

## Scenarios

| ID | Caller | Distributor address/code | Interfaces | Reported Kernel | RD local | Execution gas limit | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-CTOR-P01 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | Fuzz enabled/disabled | Fuzz [1, `type(uint32).max`]; guarantee both endpoints | Deployment succeeds | Distributor stored; execution limit equals input; minimum attempt gas 250,000; reserve 100,000; cursor 0; task disabled with 7-day grace | Covered: [fuzz][test_whenDistributorIsCompatible_initializesDefaults], [boundaries][test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit] |
| RDTASK-CTOR-I01 | Deployer | address(0) | None | Not applicable | Not applicable | Valid nonzero | RevenueDistributorTask_InvalidDistributor(address(0)) | No policy deployed | Covered: [test][test_whenDistributorIsZero_reverts] |
| RDTASK-CTOR-I02 | Deployer | EOA | None | Not applicable | Not applicable | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenDistributorIsEoa_reverts] |
| RDTASK-CTOR-I03 | Deployer | Nonzero contract | Lacks IRevenueDistributor; fuzz IEnabler support | Any | Fuzz enabled/disabled when readable | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenDistributorInterfaceIsMissing_reverts] |
| RDTASK-CTOR-I06 | Deployer | Nonzero contract | IRevenueDistributor but lacks IEnabler | Any | Not readable through the required interface | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenEnablerInterfaceIsMissing_reverts] |
| RDTASK-CTOR-I04 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Different Kernel | Fuzz enabled/disabled | Valid nonzero | RevenueDistributorTask_KernelMismatch(expected, actual) | No policy deployed | Covered: [test][test_whenDistributorUsesDifferentKernel_reverts] |
| RDTASK-CTOR-I05 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | Fuzz enabled/disabled | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | No policy deployed | Covered: [test][test_whenExecutionGasLimitIsZero_reverts] |

[test_whenDistributorIsCompatible_initializesDefaults]: ./constructor.t.sol#L13
[test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit]: ./constructor.t.sol#L73
[test_whenDistributorIsZero_reverts]: ./constructor.t.sol#L42
[test_whenDistributorIsEoa_reverts]: ./constructor.t.sol#L48
[test_whenDistributorInterfaceIsMissing_reverts]: ./constructor.t.sol#L57
[test_whenEnablerInterfaceIsMissing_reverts]: ./constructor.t.sol#L90
[test_whenDistributorUsesDifferentKernel_reverts]: ./constructor.t.sol#L98
[test_whenExecutionGasLimitIsZero_reverts]: ./constructor.t.sol#L114

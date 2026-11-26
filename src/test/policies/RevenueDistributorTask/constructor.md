# RevenueDistributorTask constructor scenario plan

Source: [RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol).

Scope: constructor deployment and directly initialized getters.

The distributor must advertise both `IRevenueDistributor` and `IEnabler`. Construction does not
require the distributor to be locally enabled; `enable` and `reEnable` own that live-state check.
A zero distributor gives `RevenueDistributorTask_InvalidDistributor(address(0))`; the constructor
also requires `IEnabler` compatibility.

## Scenarios

| ID | Caller | Distributor address/code | Interfaces | Reported Kernel | Distributor enabled | Execution gas limit | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RDTASK-CTOR-P01 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | true | Fuzz [1, `type(uint32).max`]; guarantee both endpoints | Deployment succeeds | Distributor stored; execution limit equals input; minimum attempt gas 250,000; reserve 100,000; cursor 0; task disabled with 7-day grace | Covered: [test][test_whenDistributorIsCompatible_initializesDefaults], [test][test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-P02 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | false | Fuzz [1, `type(uint32).max`]; guarantee both endpoints | Deployment succeeds | Distributor stored; execution limit equals input; minimum attempt gas 250,000; reserve 100,000; cursor 0; task disabled with 7-day grace | Covered: [test][test_whenDistributorIsCompatible_initializesDefaults], [test][test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I01 | Deployer | address(0) | None | Not applicable | true | Valid nonzero | RevenueDistributorTask_InvalidDistributor(address(0)) | No policy deployed | Covered: [test][test_whenDistributorIsZero_reverts] |
| RDTASK-CTOR-I02 | Deployer | EOA | None | Not applicable | true | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenDistributorIsEoa_reverts] |
| RDTASK-CTOR-I03 | Deployer | Nonzero contract | Lacks IRevenueDistributor; fuzz IEnabler support | Any | true | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenDistributorInterfaceIsMissing_reverts], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I07 | Deployer | Nonzero contract | Lacks IRevenueDistributor; fuzz IEnabler support | Any | false | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenDistributorInterfaceIsMissing_reverts], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I06 | Deployer | Nonzero contract | IRevenueDistributor but lacks IEnabler | Any | true | Valid nonzero | RevenueDistributorTask_InvalidDistributor(target) | No policy deployed | Covered: [test][test_whenEnablerInterfaceIsMissing_reverts] |
| RDTASK-CTOR-I04 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Different Kernel | true | Valid nonzero | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | No policy deployed | Covered: [test][test_whenDistributorUsesDifferentKernel_reverts], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I08 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Different Kernel | false | Valid nonzero | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | No policy deployed | Covered: [test][test_whenDistributorUsesDifferentKernel_reverts], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I05 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | true | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | No policy deployed | Covered: [test][test_whenExecutionGasLimitIsZero_reverts], [test][test_givenConstructorStateAndLimitSeeds] |
| RDTASK-CTOR-I09 | Deployer | Nonzero contract | IRevenueDistributor and IEnabler | Constructor Kernel | false | 0 | RevenueDistributorTask_InvalidExecutionGasLimit() | No policy deployed | Covered: [test][test_whenExecutionGasLimitIsZero_reverts], [test][test_givenConstructorStateAndLimitSeeds] |

## Untrusted metadata

| ID | Caller | Required read | Return domain | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDTASK-CTOR-D01 | Deployer | kernel() | Failed shape: empty, short, oversized or noncanonical address word | PolicyDependency_InvalidDependency(RD) | No deployment | Covered: [test][test_whenDistributorKernelReadIsMalformed_reverts], [test][test_whenDistributorMetadataBoundaries_reverts] |
| RDTASK-CTOR-D02 | Deployer | isEnabled() | Failed shape: empty, short, oversized or bool word greater than1 | PolicyDependency_InvalidDependency(RD) | No deployment | Covered: [test][test_whenDistributorEnabledReadIsMalformed_reverts], [test][test_whenDistributorMetadataBoundaries_reverts] |
| RDTASK-CTOR-D03 | Deployer | Fuzz Kernel/status getter | Reverts with arbitrary candidate error | PolicyDependency_InvalidDependency(RD) | No bubbled candidate error or deployment | Covered: [test][test_whenDistributorMetadataReverts_reverts] |

[test_whenDistributorIsCompatible_initializesDefaults]: ./constructor.t.sol#L15
[test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit]: ./constructor.t.sol#L75
[test_whenDistributorIsZero_reverts]: ./constructor.t.sol#L44
[test_whenDistributorIsEoa_reverts]: ./constructor.t.sol#L50
[test_whenDistributorInterfaceIsMissing_reverts]: ./constructor.t.sol#L59
[test_whenEnablerInterfaceIsMissing_reverts]: ./constructor.t.sol#L92
[test_whenDistributorUsesDifferentKernel_reverts]: ./constructor.t.sol#L100
[test_whenExecutionGasLimitIsZero_reverts]: ./constructor.t.sol#L117
[test_whenDistributorKernelReadIsMalformed_reverts]: ./constructor.t.sol#L139
[test_whenDistributorMetadataBoundaries_reverts]: ./constructor.t.sol#L165
[test_whenDistributorEnabledReadIsMalformed_reverts]: ./constructor.t.sol#L152
[test_whenDistributorMetadataReverts_reverts]: ./constructor.t.sol#L178
[test_givenConstructorStateAndLimitSeeds]: ./constructor.t.sol#L194

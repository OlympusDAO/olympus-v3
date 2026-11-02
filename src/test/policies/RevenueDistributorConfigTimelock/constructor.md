# RevenueDistributorConfigTimelock constructor scenario plan

Source: [RevenueDistributorConfigTimelock](../../../policies/RevenueDistributorConfigTimelock.sol).

Scope: constructor deployment and directly initialized getters.

## Scenarios

| ID | Caller | Constructor parameter / dependency condition | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-CTOR-P01 | Deployer | Nonzero target supports IRevenueDistributor, IRevenueDistributorRescue, IConfigOperator and IEnabler and uses the same Kernel | Deployment succeeds | Distributor is stored; disabled; grace is 7 days; delay is 1 day; next action ID is 1; execution window is 3 days; maximum batch keys is 15 | Covered: [evidence][test_whenConstructedWithValidTarget_setsTargetAndDefaults] |
| RDCT-CTOR-I01 | Deployer | Target is address(0) | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenConstructedWithZeroTarget_reverts] |
| RDCT-CTOR-I02 | Deployer | Target is an EOA | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenConstructedWithEoaTarget_reverts] |
| RDCT-CTOR-I03 | Deployer | Contract lacks IRevenueDistributor | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksRevenueDistributorInterface_reverts] |
| RDCT-CTOR-I04 | Deployer | Contract lacks IRevenueDistributorRescue | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksRescueInterface_reverts] |
| RDCT-CTOR-I05 | Deployer | Contract lacks IConfigOperator | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksConfigOperatorInterface_reverts] |
| RDCT-CTOR-I06 | Deployer | Contract lacks IEnabler | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksEnablerInterface_reverts] |
| RDCT-CTOR-I07 | Deployer | Compatible target uses another Kernel | PolicyDependency_KernelMismatch(RD,expectedKernel,reportedKernel) | No policy deployed | Covered: [test][test_whenTargetUsesDifferentKernel_reverts] |

[test_whenConstructedWithValidTarget_setsTargetAndDefaults]: ./constructor.t.sol#L19
[test_whenConstructedWithZeroTarget_reverts]: ./constructor.t.sol#L36
[test_whenConstructedWithEoaTarget_reverts]: ./constructor.t.sol#L42
[test_whenTargetLacksRevenueDistributorInterface_reverts]: ./constructor.t.sol#L50
[test_whenTargetLacksRescueInterface_reverts]: ./constructor.t.sol#L64
[test_whenTargetLacksConfigOperatorInterface_reverts]: ./constructor.t.sol#L78
[test_whenTargetLacksEnablerInterface_reverts]: ./constructor.t.sol#L92
[test_whenTargetUsesDifferentKernel_reverts]: ./constructor.t.sol#L106

## Untrusted metadata

| ID | Caller | Required read | Return domain | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-CTOR-D01 | Deployer | kernel() | Failed shape: empty, short, oversized or noncanonical address word | PolicyDependency_InvalidDependency(RD) | No deployment | Covered: [test][test_whenDistributorKernelReadIsMalformed_reverts], [test][test_whenDistributorMetadataBoundaries_reverts] |
| RDCT-CTOR-D02 | Deployer | isEnabled() | Failed shape: empty, short, oversized or bool word greater than1 | PolicyDependency_InvalidDependency(RD) | No deployment | Covered: [test][test_whenDistributorEnabledReadIsMalformed_reverts], [test][test_whenDistributorMetadataBoundaries_reverts] |
| RDCT-CTOR-D03 | Deployer | Fuzz Kernel/status getter | Reverts with MetadataFailed() | PolicyDependency_InvalidDependency(RD) | No bubbled candidate error or deployment | Covered: [test][test_whenDistributorMetadataReverts_reverts] |

[test_whenDistributorKernelReadIsMalformed_reverts]: ./constructor.t.sol#L139
[test_whenDistributorMetadataBoundaries_reverts]: ./constructor.t.sol#L165
[test_whenDistributorEnabledReadIsMalformed_reverts]: ./constructor.t.sol#L152
[test_whenDistributorMetadataReverts_reverts]: ./constructor.t.sol#L178

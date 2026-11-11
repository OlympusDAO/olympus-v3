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

## Untrusted metadata

| ID | Caller | Required read | Return domain | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| RDCT-CTOR-D01 | Deployer | kernel() | Failed shape: empty, short, oversized or noncanonical address word | PolicyDependency_InvalidDependency(RD) | No deployment | Covered: [test][test_whenDistributorKernelReadIsMalformed_reverts], [test][test_whenDistributorMetadataBoundaries_reverts] |
| RDCT-CTOR-D02 | Deployer | No isEnabled read | Arbitrary return data, including empty, short, oversized or dirty bool | Success | Target bound and queue disabled; status metadata unused | Covered: [test][test_whenDistributorEnabledReadIsMalformed_thenConstructed], [test][test_whenEnabledMetadataBoundarySeeds_thenConstructed] |
| RDCT-CTOR-D03 | Deployer | kernel() | Reverts with MetadataFailed() | PolicyDependency_InvalidDependency(RD) | No bubbled candidate error or deployment | Covered: [test][test_whenDistributorMetadataReverts_reverts] |

## Deployment before runtime readiness

Construction validates the full consumed interface set and same-Kernel binding, shared with enable/reEnable compatibility checks. Target activity, local enablement and configOperator selection are runtime prerequisites only; none is read at construction.

| ID | Caller | Target condition | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-CTOR-P02 | Fuzz deployer | Activity, isEnabled and configOperator reads revert; interfaces/Kernel binding valid | Success | No lifecycle/selection reads; queue disabled | Covered: [test][test_givenRuntimeReadinessGettersRevert_whenConstructed] |
| RDCT-CTOR-P03 | Deployer | All four independent target active/enabled pairs | Success | Exact target binding; queue disabled independently of target | Covered: [test][test_givenAnyTargetLifecycle_whenConstructed], [test][test_givenTargetLifecycleSeeds_whenConstructed] |

[test_whenConstructedWithValidTarget_setsTargetAndDefaults]: ./constructor.t.sol#L19
[test_whenConstructedWithZeroTarget_reverts]: ./constructor.t.sol#L36
[test_whenConstructedWithEoaTarget_reverts]: ./constructor.t.sol#L42
[test_whenTargetLacksRevenueDistributorInterface_reverts]: ./constructor.t.sol#L50
[test_whenTargetLacksRescueInterface_reverts]: ./constructor.t.sol#L64
[test_whenTargetLacksConfigOperatorInterface_reverts]: ./constructor.t.sol#L78
[test_whenTargetLacksEnablerInterface_reverts]: ./constructor.t.sol#L92
[test_whenTargetUsesDifferentKernel_reverts]: ./constructor.t.sol#L106
[test_whenDistributorKernelReadIsMalformed_reverts]: ./constructor.t.sol#L139
[test_whenDistributorMetadataBoundaries_reverts]: ./constructor.t.sol#L169
[test_whenDistributorEnabledReadIsMalformed_thenConstructed]: ./constructor.t.sol#L152
[test_whenDistributorMetadataReverts_reverts]: ./constructor.t.sol#L178
[test_givenAnyTargetLifecycle_whenConstructed]: ./constructor.t.sol#L228
[test_givenRuntimeReadinessGettersRevert_whenConstructed]: ./constructor.t.sol#L202
[test_givenTargetLifecycleSeeds_whenConstructed]: ./constructor.t.sol#L244
[test_whenEnabledMetadataBoundarySeeds_thenConstructed]: ./constructor.t.sol#L194

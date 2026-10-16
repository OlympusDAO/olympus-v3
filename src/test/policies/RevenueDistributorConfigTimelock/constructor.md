# RevenueDistributorConfigTimelock constructor scenario plan

Scope: constructor deployment and directly initialized getters.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RDCT-CTOR-P01 | Deployer | Nonzero target supports IRevenueDistributor, IRevenueDistributorRescue, IConfigOperator and IEnabler and uses the same Kernel | Deployment succeeds | Distributor is stored; disabled; grace is 7 days; delay is 1 day; next action ID is 1; execution window is 3 days; maximum batch keys is 15 | Covered: [evidence][test_whenConstructedWithValidTarget_setsTargetAndDefaults] |
| RDCT-CTOR-I01 | Deployer | Target is address(0) | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenConstructedWithZeroTarget_reverts] |
| RDCT-CTOR-I02 | Deployer | Target is an EOA | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenConstructedWithEoaTarget_reverts] |
| RDCT-CTOR-I03 | Deployer | Contract lacks IRevenueDistributor | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksRevenueDistributorInterface_reverts] |
| RDCT-CTOR-I04 | Deployer | Contract lacks IRevenueDistributorRescue | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksRescueInterface_reverts] |
| RDCT-CTOR-I05 | Deployer | Contract lacks IConfigOperator | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksConfigOperatorInterface_reverts] |
| RDCT-CTOR-I06 | Deployer | Contract lacks IEnabler | RevenueDistributorConfigTimelock_InvalidDistributor(target) | No policy deployed | Covered: [evidence][test_whenTargetLacksEnablerInterface_reverts] |
| RDCT-CTOR-I07 | Deployer | Compatible target uses another Kernel | RevenueDistributorConfigTimelock_KernelMismatch(targetKernel) | No policy deployed | Covered: [evidence][test_whenTargetUsesDifferentKernel_reverts] |

[test_whenConstructedWithValidTarget_setsTargetAndDefaults]: ./constructor.t.sol#L21
[test_whenConstructedWithZeroTarget_reverts]: ./constructor.t.sol#L38
[test_whenConstructedWithEoaTarget_reverts]: ./constructor.t.sol#L44
[test_whenTargetLacksRevenueDistributorInterface_reverts]: ./constructor.t.sol#L52
[test_whenTargetLacksRescueInterface_reverts]: ./constructor.t.sol#L66
[test_whenTargetLacksConfigOperatorInterface_reverts]: ./constructor.t.sol#L80
[test_whenTargetLacksEnablerInterface_reverts]: ./constructor.t.sol#L94
[test_whenTargetUsesDifferentKernel_reverts]: ./constructor.t.sol#L108

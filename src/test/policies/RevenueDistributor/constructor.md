# RevenueDistributor constructor scenario plan

Scope: constructor deployment and its directly initialized getters.

## Scenarios

| ID | Caller | State and inputs | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| RD-CTOR-P01 | Deployer | Nonzero Kernel | Deployment succeeds | `kernel` equals input; disabled; grace period is 7 days; transition timestamp, config operator, active assets and pending assets are empty | Covered: [evidence][test_whenConstructedWithKernel_initializesDefaults] |
| RD-CTOR-P02 | Deployer | Kernel is address(0) | Deployment succeeds because the constructor does not validate the pointer | `kernel` is zero; all other defaults match RD-CTOR-P01 | Covered: [evidence][test_whenConstructedWithZeroKernel_preservesZeroPointer] |

[test_whenConstructedWithKernel_initializesDefaults]: ./constructor.t.sol#L13
[test_whenConstructedWithZeroKernel_preservesZeroPointer]: ./constructor.t.sol#L31

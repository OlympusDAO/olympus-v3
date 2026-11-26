# BurnerLoansDebt.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansDebt.sol#L44). Implemented and mapped to the focused Foundry suite.

## Domains and notation

Scenario scope: `BLDEBT-CONSTRUCTOR` identifies this contract/function.

Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)`. Missing required interfaces use `BurnerLoansAction_InvalidCore(Core)`.

Kernel and Core; Core must expose IBurnerLoansCore, IEnabler and IOperatorAuth via ERC165, sameKernel. No initial Core active/enabled requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Deployment inputs

| ID | Caller | Core active | Core enabled | Input / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-CONSTRUCTOR-I01 | Fuzz deployer | N/A: no deployed candidate | N/A: no deployed candidate | Core=address(0) | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenCoreZero_reverts][test_whenCoreZero_reverts] |
| BLDEBT-CONSTRUCTOR-I02 | Fuzz deployer | N/A: no deployed candidate | N/A: no deployed candidate | Core is an EOA | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenCoreEOA_reverts][test_whenCoreEOA_reverts] |
| BLDEBT-CONSTRUCTOR-I03 | Fuzz deployer | true | true | Core lacks IBurnerLoansCore but advertises IEnabler | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_givenMissingCoreInterface_whenDeployed_reverts][test_givenMissingCoreInterface_whenDeployed_reverts] |
| BLDEBT-CONSTRUCTOR-I04 | Fuzz deployer | true | true | Core advertises IBurnerLoansCore but lacks IEnabler | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_givenMissingCoreInterface_whenDeployed_reverts][test_givenMissingCoreInterface_whenDeployed_reverts] |
| BLDEBT-CONSTRUCTOR-I05 | Fuzz deployer | true | true | ERC165 supportsInterface reverts | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_givenBrokenERC165_whenDeployed_reverts][test_givenBrokenERC165_whenDeployed_reverts] |
| BLDEBT-CONSTRUCTOR-I06 | Fuzz deployer | true | true | ERC165 supportsInterface returns malformed data | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_givenBrokenERC165_whenDeployed_reverts][test_givenBrokenERC165_whenDeployed_reverts] |
| BLDEBT-CONSTRUCTOR-I07 | Fuzz deployer | true | true | All required interfaces supported; Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel) | No deployment or committed logs | Covered: [test_givenDifferentKernel_whenDeployed_reverts][test_givenDifferentKernel_whenDeployed_reverts] |
| BLDEBT-CONSTRUCTOR-I08 | Fuzz deployer | true | true | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds][test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds], [test_whenBoundToCore_thenDeploymentIndependentOfLifecycle][test_whenBoundToCore_thenDeploymentIndependentOfLifecycle] |
| BLDEBT-CONSTRUCTOR-I09 | Fuzz deployer | true | false | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds][test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds], [test_whenBoundToCore_thenDeploymentIndependentOfLifecycle][test_whenBoundToCore_thenDeploymentIndependentOfLifecycle] |
| BLDEBT-CONSTRUCTOR-I10 | Fuzz deployer | false | true | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds][test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds], [test_whenBoundToCore_thenDeploymentIndependentOfLifecycle][test_whenBoundToCore_thenDeploymentIndependentOfLifecycle] |
| BLDEBT-CONSTRUCTOR-I11 | Fuzz deployer | false | false | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds][test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds], [test_whenBoundToCore_thenDeploymentIndependentOfLifecycle][test_whenBoundToCore_thenDeploymentIndependentOfLifecycle] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `core`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenBrokenERC165_whenDeployed_reverts]: constructor.t.sol#L48
[test_givenDifferentKernel_whenDeployed_reverts]: constructor.t.sol#L60
[test_givenMissingCoreInterface_whenDeployed_reverts]: constructor.t.sol#L36
[test_whenBoundToCore_thenDeploymentIndependentOfLifecycle]: constructor.t.sol#L74
[test_whenCoreEOA_reverts]: constructor.t.sol#L29
[test_whenCoreLifecycleAxesSeeded_thenDeploymentStillBinds]: constructor.t.sol#L104
[test_whenCoreZero_reverts]: constructor.t.sol#L23

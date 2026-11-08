# BurnerLoansCollateral.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansCollateral.sol#L34). Test mappings describe the verified scope of each named test.

## Domains and notation

Scenario scope: `BLCOL-CONSTRUCTOR` identifies this contract/function.

Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)`. Missing required interfaces use `BurnerLoansAction_InvalidCore(Core)`.

Kernel and Core; Core must expose IBurnerLoansCore, IEnabler and IOperatorAuth via ERC165, sameKernel. No initial Core active/enabled requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Deployment inputs

| ID | Caller | Core active | Core enabled | Input / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-CONSTRUCTOR-I01 | Fuzz deployer | N/A: no deployed candidate | N/A: no deployed candidate | Core=address(0) | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenCoreZero_reverts][test_whenCoreZero_reverts] |
| BLCOL-CONSTRUCTOR-I02 | Fuzz deployer | N/A: no deployed candidate | N/A: no deployed candidate | Core is an EOA | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenCoreEOA_reverts][test_whenCoreEOA_reverts] |
| BLCOL-CONSTRUCTOR-I03 | Fuzz deployer | true | true | Core lacks IBurnerLoansCore but advertises IEnabler | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenCoreInterfaceMissing_reverts][test_whenCoreInterfaceMissing_reverts] |
| BLCOL-CONSTRUCTOR-I04 | Fuzz deployer | true | true | Core advertises IBurnerLoansCore but lacks IEnabler | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenEnablerInterfaceMissing_reverts][test_whenEnablerInterfaceMissing_reverts] |
| BLCOL-CONSTRUCTOR-I12 | Fuzz deployer | true | true | Core supports IBurnerLoansCore and IEnabler but lacks IOperatorAuth | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_givenMissingOperatorAuthInterface_whenDeployed_reverts][test_givenMissingOperatorAuthInterface_whenDeployed_reverts] |
| BLCOL-CONSTRUCTOR-I05 | Fuzz deployer | true | true | ERC165 supportsInterface reverts | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenERC165Reverts_reverts][test_whenERC165Reverts_reverts] |
| BLCOL-CONSTRUCTOR-I06 | Fuzz deployer | true | true | ERC165 supportsInterface returns malformed data | BurnerLoansAction_InvalidCore(candidate) | No deployment or committed logs | Covered: [test_whenERC165Malformed_reverts][test_whenERC165Malformed_reverts] |
| BLCOL-CONSTRUCTOR-I07 | Fuzz deployer | true | true | All required interfaces supported; Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel) | No deployment or committed logs | Covered: [test_whenCoreKernelDiffers_reverts][test_whenCoreKernelDiffers_reverts] |
| BLCOL-CONSTRUCTOR-I08 | Fuzz deployer | true | true | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenValidCoreBinding][test_whenValidCoreBinding], [test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent][test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent] |
| BLCOL-CONSTRUCTOR-I09 | Fuzz deployer | true | false | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenValidCoreBinding][test_whenValidCoreBinding], [test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent][test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent] |
| BLCOL-CONSTRUCTOR-I10 | Fuzz deployer | false | true | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenValidCoreBinding][test_whenValidCoreBinding], [test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent][test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent] |
| BLCOL-CONSTRUCTOR-I11 | Fuzz deployer | false | false | Compatible Core; | Success | Immutable Core/Kernel exact; action disabled; lastTransitionAt=0; gracePeriod=7 days; GracePeriodSet(7 days); no funding/grant | Covered: [test_whenValidCoreBinding][test_whenValidCoreBinding], [test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent][test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `core`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Focused implementation status

Constructor and lifecycle suites pass with solc 0.8.36, optimizer 400 and no via IR. This fixture uses real Kernel/ROLES and an existing enabled-policy mock for the Core identity. It does not prove real loan/custody preservation, settlement callbacks, or the full boundary/payload seed matrix. Deposit/withdrawal units and real-dependency integration remain pending.

[test_givenMissingOperatorAuthInterface_whenDeployed_reverts]: constructor.t.sol#L27
[test_whenCoreEOA_reverts]: constructor.t.sol#L51
[test_whenCoreInterfaceMissing_reverts]: constructor.t.sol#L59
[test_whenCoreKernelDiffers_reverts]: constructor.t.sol#L105
[test_whenCoreLifecycleSeedsUsed_thenInitializationIsIndependent]: constructor.t.sol#L165
[test_whenCoreZero_reverts]: constructor.t.sol#L44
[test_whenERC165Malformed_reverts]: constructor.t.sol#L90
[test_whenERC165Reverts_reverts]: constructor.t.sol#L75
[test_whenEnablerInterfaceMissing_reverts]: constructor.t.sol#L67
[test_whenValidCoreBinding]: constructor.t.sol#L120

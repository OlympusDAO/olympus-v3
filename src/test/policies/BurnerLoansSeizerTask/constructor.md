# BurnerLoansSeizerTask.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L88). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSZC` identifies this contract/function.

Implemented constructor binding: accept a directly bound Lens. Kernel, IBurnerLoansSeize, IBurnerLoansLens, check:uint16, seize:uint8, gas:uint32. Derive Core from Seize.core() and compare it with Lens.core(). Lens is a plain helper without its own Kernel; Seize must report the Task Kernel. Task validates the derived Core interface because addAsset calls Core.isAssetRegistered() directly. Seize owns Core Kernel and operational-readiness validation. There is no separately configured Core dependency or Core lifecycle gate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Fixed for this table: Accounting / events: Immutable Seize/Lens bindings sharing a derived Core; no deployment-time lifecycle/role gate.

| ID | Caller | Seize active | Seize enabled | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSZC-L01 | Fuzz all deployers | true | false | Other constructor inputs valid; | Success | Covered: [test][test_givenSeizeLifecycleState_whenDeployed_thenBindingStillSucceeds] |
| BLSZC-L02 | Fuzz all deployers | false | true | Other constructor inputs valid; | Success | Covered: [test][test_givenSeizeLifecycleState_whenDeployed_thenBindingStillSucceeds] |
| BLSZC-L03 | Fuzz all deployers | false | false | Other constructor inputs valid; | Success | Covered: [test][test_givenSeizeLifecycleState_whenDeployed_thenBindingStillSucceeds] |

## Dependency compatibility

Fixed for this table: Other bindings and inputs valid; Accounting / events: No deployment or committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSZC-D01 | Fuzz all deployers | Seize lacks IBurnerLoansSeize | BurnerLoansSeizer_InvalidSeize(Seize) | Covered: [test][test_whenSeizeInterfaceInvalid_reverts] |
| BLSZC-D02 | Fuzz all deployers | Seize ERC165 reverts | BurnerLoansSeizer_InvalidSeize(Seize) | Covered: [test][test_whenSeizeInterfaceInvalid_reverts] |
| BLSZC-D03 | Fuzz all deployers | Seize ERC165 returns malformed data | BurnerLoansSeizer_InvalidSeize(Seize) | Covered: [test][test_whenSeizeInterfaceInvalid_reverts] |
| BLSZC-D05 | Fuzz all deployers | Seize and Lens report different Cores | BurnerLoansSeizer_InvalidLens(Lens) | Covered: [test][test_whenLensReportsDifferentCore_reverts] |
| BLSZC-D06 | Fuzz all deployers | Seize reports another Kernel | PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel) | Covered: [test][test_whenSeizeReportsDifferentKernel_reverts] |

Retired ID: BLSZC-D04. Seize validates its own Core binding; Task validates Seize and compares the shared Core identity with Lens.

## Invalid inputs

Fixed for this table: Other bindings and inputs valid; Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSZC-I04 | Fuzz all deployers | Seize=0 | BurnerLoansSeizer_InvalidSeize(address(0)) | Covered: [test][test_whenSeizeZero_reverts] |
| BLSZC-I05 | Fuzz all deployers | Seize is EOA | BurnerLoansSeizer_InvalidSeize(Seize) | Covered: [test][test_whenSeizeHasNoCode_reverts] |
| BLSZC-I06 | Fuzz all deployers | maxBorrowersToCheck=0; other limits valid | BurnerLoansSeizer_InvalidScanLimits(check,seize) | Covered: [test][test_whenScanLimitZero_reverts] |
| BLSZC-I07 | Fuzz all deployers | maxBorrowersToSeize=0; other limits valid | BurnerLoansSeizer_InvalidScanLimits(check,seize) | Covered: [test][test_whenSeizeLimitZero_reverts] |
| BLSZC-I08 | Fuzz all deployers | maxBorrowersToSeize>maxBorrowersToCheck | BurnerLoansSeizer_InvalidScanLimits(check,seize) | Covered: [test][test_whenSeizeLimitExceedsScanLimit_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Other bindings and inputs valid; Accounting / events: No deployment or committed logs.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSZC-N01 | Fuzz all deployers | check fuzz 1..MAX16; seize fuzz 1..min(check,MAX8); seed 1/1,501/51,MAX16/MAX8 | Success; no additional 500/50 ceiling | Covered: [test][test_whenBindingsMatch_thenCoreIsDerived], [test][test_whenConstructorBoundariesSeeded_thenAccepted] |

## Successful execution

Fixed for this table: other bindings and inputs valid.

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSZC-P02 | Fuzz all deployers | Seize binding getter reverts | Exact configured dependency error | No deployment or committed logs | Covered: [test][test_whenSeizeCoreGetterReverts_thenErrorPropagates] |
| BLSZC-P03 | Fuzz all deployers | Other constructor inputs valid; | Success | Immutable Seize/Lens bindings sharing a derived Core; no deployment-time lifecycle/role gate | Covered: [test][test_whenBindingsMatch_thenCoreIsDerived], [test][test_whenConstructorBoundariesSeeded_thenAccepted], [direct dependency][test_whenCoreLifecycleUnreadable_thenDeploymentUsesSeizeBinding] |

## Scanning and progress

Fixed for this table: other bindings and inputs valid.

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSZC-P04 | Fuzz all deployers | executionGasLimit=0; scan limits valid | BurnerLoansSeizer_InvalidExecutionGasLimit() | No deployment or committed logs | Covered: [test][test_whenConstructorGasLimitZero_reverts] |
| BLSZC-P05 | Fuzz all deployers | Valid scan limits; executionGasLimit fuzz 1..MAX32; seed 1,MAX32 | Success | Immutable Seize/Lens bindings sharing a derived Core; stored scan/gas limits; empty assets/cursors; disabled; grace7 days | Covered: [test][test_whenBindingsMatch_thenCoreIsDerived], [test][test_whenConstructorBoundariesSeeded_thenAccepted] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `seize`, `lens`, and the Core derived through `seize().core()`. Assert each binding independently.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Test organization

[constructor.t.sol](./constructor.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Direct scan-helper binding

Lens has no local Enabler or Kernel activation. Core is a dependency of Lens, never the reverse. SeizerTask binds Lens directly at construction; replacing this immutable helper requires deploying a new SeizerTask, avoiding a registry on Core. All other constructor inputs valid.

| ID | Caller | Lens condition | Result | Test |
| --- | --- | --- | --- | --- |
| BLSZC-I01 | Fuzz deployer | Lens=0 | BurnerLoansSeizer_InvalidLens(candidate) | Covered: [test][test_whenLensHasNoCode_reverts], [test][test_whenLensZero_reverts] |
| BLSZC-I02 | Fuzz deployer | Lens nonzero EOA | BurnerLoansSeizer_InvalidLens(candidate) | Covered: [test][test_whenLensHasNoCode_reverts] |
| BLSZC-I03 | Fuzz deployer | Lens.core() reports another Core | BurnerLoansSeizer_InvalidLens(candidate) | Covered: [test][test_whenLensReportsDifferentCore_reverts] |
| BLSZC-T01 | Fuzz deployer | Lens.core() getter reverts | Exact configured getter error | Covered: [test][test_whenLensCoreGetterReverts_thenErrorPropagates] |
| BLSZC-P01 | Fuzz deployer | Deployed Lens bound to same Core | Store Lens directly; no Core.lens() discovery | Covered: [test][test_whenBindingsMatch_thenCoreIsDerived], [test][test_whenConstructorBoundariesSeeded_thenAccepted] |

## Core interface admission

Seize and Lens report the same Core; all other constructor inputs are valid. Core Kernel metadata, activity and local enablement are independent of this compatibility check. Rejection creates no contract or committed logs.

| ID | Caller | Derived Core | Result | Test |
| --- | --- | --- | --- | --- |
| BLSZC-D07 | Fuzz deployers | Zero address | BurnerLoansSeizerTask_InvalidCore(Core) | Covered: [test][test_givenZeroCore_whenConstructed_reverts] |
| BLSZC-D08 | Fuzz deployers | Nonzero EOA | BurnerLoansSeizerTask_InvalidCore(Core) | Covered: [test][test_givenEoaCore_whenConstructed_reverts] |
| BLSZC-D09 | Fuzz deployers | Missing IBurnerLoansCore support | BurnerLoansSeizerTask_InvalidCore(Core) | Covered: [test][test_givenMissingCoreInterface_whenConstructed_reverts] |
| BLSZC-D10 | Fuzz deployers | Core interface probe reverts | BurnerLoansSeizerTask_InvalidCore(Core) | Covered: [test][test_givenRevertingCoreInterface_whenConstructed_reverts] |
| BLSZC-D11 | Fuzz deployers | Core interface probe returns short data | BurnerLoansSeizerTask_InvalidCore(Core) | Covered: [test][test_givenMalformedCoreInterface_whenConstructed_reverts] |
| BLSZC-P06 | Fuzz deployers | Compatible Core; active/enabled flags independently false/true, with all four seeded | Success; initial Task defaults preserved | Covered: [test][test_givenCoreLifecycle_whenConstructed]; [seeds][test_whenCoreLifecycleStatesSeeded_thenAccepted] |

[test_givenSeizeLifecycleState_whenDeployed_thenBindingStillSucceeds]: ./constructor.t.sol#L166
[test_whenBindingsMatch_thenCoreIsDerived]: ./constructor.t.sol#L26
[test_whenConstructorBoundariesSeeded_thenAccepted]: ./constructor.t.sol#L256
[test_whenConstructorGasLimitZero_reverts]: ./constructor.t.sol#L250
[test_whenSeizeInterfaceInvalid_reverts]: ./constructor.t.sol#L190
[test_whenLensCoreGetterReverts_thenErrorPropagates]: ./constructor.t.sol#L284
[test_whenLensHasNoCode_reverts]: ./constructor.t.sol#L92
[test_whenLensReportsDifferentCore_reverts]: ./constructor.t.sol#L104
[test_whenLensZero_reverts]: ./constructor.t.sol#L268
[test_whenScanLimitZero_reverts]: ./constructor.t.sol#L210
[test_whenSeizeCoreGetterReverts_thenErrorPropagates]: ./constructor.t.sol#L273
[test_whenSeizeHasNoCode_reverts]: ./constructor.t.sol#L80
[test_whenSeizeLimitExceedsScanLimit_reverts]: ./constructor.t.sol#L236
[test_whenSeizeLimitZero_reverts]: ./constructor.t.sol#L223
[test_whenSeizeReportsDifferentKernel_reverts]: ./constructor.t.sol#L121
[test_whenSeizeZero_reverts]: ./constructor.t.sol#L68

[test_whenCoreLifecycleUnreadable_thenDeploymentUsesSeizeBinding]: ./constructor.t.sol#L140

[test_givenZeroCore_whenConstructed_reverts]: ./constructor.t.sol#L321

[test_givenEoaCore_whenConstructed_reverts]: ./constructor.t.sol#L329

[test_givenMissingCoreInterface_whenConstructed_reverts]: ./constructor.t.sol#L338

[test_givenRevertingCoreInterface_whenConstructed_reverts]: ./constructor.t.sol#L350

[test_givenMalformedCoreInterface_whenConstructed_reverts]: ./constructor.t.sol#L362

[test_givenCoreLifecycle_whenConstructed]: ./constructor.t.sol#L374
[test_whenCoreLifecycleStatesSeeded_thenAccepted]: ./constructor.t.sol#L384

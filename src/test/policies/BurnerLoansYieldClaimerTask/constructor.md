# BurnerLoansYieldClaimerTask.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L87). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-CONSTRUCTOR` identifies this contract/function.

Kernel,Core,executionGasLimit:uint32. Core and lifecycle interfaces required.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Fixed for this table: Accounting / events: Immutable Core/Kernel; initial task limits; disabled.

| ID | Caller | Core active | Core enabled | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-CONSTRUCTOR-L01 | Fuzz all deployers | true | false | Other constructor inputs valid; | Success | Covered: [test][test_givenValidConfiguration_whenDeployed] |
| BLYC-CONSTRUCTOR-L02 | Fuzz all deployers | false | true | Other constructor inputs valid; | Success | Covered: [test][test_givenValidConfiguration_whenDeployed] |
| BLYC-CONSTRUCTOR-L03 | Fuzz all deployers | false | false | Other constructor inputs valid; | Success | Covered: [test][test_givenValidConfiguration_whenDeployed] |

Required Core compatibility error: `BurnerLoansYieldClaimer_InvalidCore(Core)`. Constructor, enable and reEnable use the same consumer-owned error for incompatible metadata.

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: No deployment or committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-CONSTRUCTOR-D01 | Fuzz all deployers | Core lacks IBurnerLoansCore | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenCoreInterfaceUnsupported_reverts] |
| BLYC-CONSTRUCTOR-D02 | Fuzz all deployers | Core lacks IEnabler | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenBurnerLoansDoesNotSupportLifecycle_reverts] |
| BLYC-CONSTRUCTOR-D03 | Fuzz all deployers | Core ERC165 reverts | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenRevertingERC165_whenDeployed_reverts] |
| BLYC-CONSTRUCTOR-D04 | Fuzz all deployers | Core ERC165 returns malformed response | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenMalformedERC165_whenDeployed_reverts], [test][test_givenNoncanonicalERC165Boolean_whenDeployed_reverts] |
| BLYC-CONSTRUCTOR-D05 | Fuzz all deployers | Required interfaces valid; Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Covered: [test][test_givenBurnerLoansUsesDifferentKernel_reverts], [test][test_givenMalformedKernel_whenDeployed_reverts], [test][test_givenRevertingKernel_whenDeployed_reverts] |

## Invalid inputs

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-CONSTRUCTOR-I01 | Fuzz all deployers | Core=0 | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenBurnerLoansIsZero_reverts] |
| BLYC-CONSTRUCTOR-I02 | Fuzz all deployers | Core is EOA | BurnerLoansYieldClaimer_InvalidCore(Core) | Covered: [test][test_givenBurnerLoansIsEoa_reverts] |

## Successful execution

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: Immutable Core/Kernel; initial task limits; disabled.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-CONSTRUCTOR-P01 | Fuzz all deployers | Other constructor inputs valid; | Success | Covered: [test][test_givenValidConfiguration_whenDeployed] |

## Scanning and progress

Fixed for this table: Core active: true; Core enabled: true.

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-CONSTRUCTOR-P02 | Fuzz all deployers | Core valid; executionGasLimit=0 | BurnerLoansYieldClaimer_InvalidExecutionGasLimit() | No deployment or committed logs | Covered: [test][test_givenExecutionGasLimitIsZero_reverts] |
| BLYC-CONSTRUCTOR-P03 | Fuzz all deployers | Core valid; executionGasLimit fuzz 1..MAX32; seed 1,MAX32 | Success | Core/burnerLoans identical; cursor0; minimumGas250000/reserve100000; disabled; grace7 days | Covered: [test][test_givenValidConfiguration_whenDeployed], [test][test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `core`, `burnerLoans`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenBurnerLoansDoesNotSupportLifecycle_reverts]: constructor.t.sol#L50
[test_givenCoreInterfaceUnsupported_reverts]: constructor.t.sol#L36
[test_givenBurnerLoansIsEoa_reverts]: constructor.t.sol#L150
[test_givenBurnerLoansIsZero_reverts]: constructor.t.sol#L24
[test_givenBurnerLoansUsesDifferentKernel_reverts]: constructor.t.sol#L64
[test_givenExecutionGasLimitIsZero_reverts]: constructor.t.sol#L83
[test_givenMalformedERC165_whenDeployed_reverts]: constructor.t.sol#L175
[test_givenMalformedKernel_whenDeployed_reverts]: constructor.t.sol#L181
[test_givenNoncanonicalERC165Boolean_whenDeployed_reverts]: constructor.t.sol#L219
[test_givenRevertingERC165_whenDeployed_reverts]: constructor.t.sol#L165
[test_givenRevertingKernel_whenDeployed_reverts]: constructor.t.sol#L191
[test_givenValidConfiguration_whenDeployed]: constructor.t.sol#L92
[test_whenExecutionGasLimitBoundariesUsed_initializesExactLimit]: constructor.t.sol#L133

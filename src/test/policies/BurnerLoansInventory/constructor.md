# BurnerLoansInventory.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansInventory.sol#L85). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-CONSTRUCTOR` identifies this contract/function.

Inventory stores Kernel, OHM and immutable Core. OHM and Core must be nonzero, and Core must support IBurnerLoansCore because configuration and surplus recovery call Core.requireNotReentrant(). Core must report the supplied Kernel. Core activity and enablement are not queried. Core owns downstream admission at setInventory, enable and reEnable.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Fixed for this table: Accounting / events: Immutable Core/OHM; Config=0; claims/idle/principal/cap=0; disabled; grace 7 days.

| ID | Caller | Core active | Core enabled | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-L01 | Fuzz all deployers | true | false | Other constructor inputs valid; | Success | Covered: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds] |
| BLINV-CONSTRUCTOR-L02 | Fuzz all deployers | false | true | Other constructor inputs valid; | Success | Covered: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds] |
| BLINV-CONSTRUCTOR-L03 | Fuzz all deployers | false | false | Other constructor inputs valid; | Success | Covered: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds] |

## Dependency compatibility

Fixed for this table: Core active/enabled flags are independent; deployment stores the supplied Core identity.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-D01 | Fuzz all deployers | Core deployed; reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Covered: [test_givenForeignKernel_whenDeployed_reverts][test_givenForeignKernel_whenDeployed_reverts] |
| BLINV-CONSTRUCTOR-D02 | Fuzz all deployers | Core does not advertise IBurnerLoansCore | BurnerLoansInventory_InvalidCore(Core) | Covered: [test][test_givenMissingCoreInterface_whenDeployed_reverts] |
| BLINV-CONSTRUCTOR-D03 | Fuzz all deployers | Core service-interface probe reverts | BurnerLoansInventory_InvalidCore(Core) | Covered: [test][test_givenRevertingCoreInterface_whenDeployed_reverts] |
| BLINV-CONSTRUCTOR-D04 | Fuzz all deployers | Core service-interface probe returns malformed bytes | BurnerLoansInventory_InvalidCore(Core) | Covered: [test][test_givenMalformedCoreInterface_whenDeployed_reverts] |
| BLINV-CONSTRUCTOR-D05 | Fuzz all deployers | Core advertises the service but lacks ERC165 | BurnerLoansInventory_InvalidCore(Core) | Covered: [test][test_givenMissingERC165_whenDeployed_reverts] |

## Invalid inputs

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-I01 | Fuzz all deployers | OHM=0; Core nonzero | BurnerLoansInventory_ZeroAddress() | Covered: [test_whenZeroOhm_reverts][test_whenZeroOhm_reverts] |
| BLINV-CONSTRUCTOR-I02 | Fuzz all deployers | OHM nonzero; Core=0; no Core interface probe | BurnerLoansInventory_InvalidCore(0) | Covered: [test_whenZeroFacility_reverts][test_whenZeroFacility_reverts] |
| BLINV-CONSTRUCTOR-I03 | Fuzz all deployers | Core is EOA | BurnerLoansInventory_InvalidCore(Core) | Covered: [test_whenFacilityHasNoCode_reverts][test_whenFacilityHasNoCode_reverts] |

## Successful execution

Fixed for this table: Core active: true; Core enabled: true.

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-P02 | Fuzz all deployers | Other constructor inputs valid; | Success | Immutable Core/OHM; Config=0; claims/idle/principal/cap=0; disabled; grace 7 days | Covered: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds] |

## Dependency call failures

| ID | Caller | Dependency behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-P01 | Fuzz all deployers | Core kernel getter reverts or returns malformed bytes | PolicyDependency_InvalidDependency(Core) | No deployment or committed logs | Covered: [test_givenCoreKernelReadFails_whenDeployed_reverts][test_givenCoreKernelReadFails_whenDeployed_reverts]; [test_givenMalformedCoreMetadata_whenDeployed_reverts][test_givenMalformedCoreMetadata_whenDeployed_reverts] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `ohm` and `core` are read directly from each new Inventory.

- [x] Review these expectations.
- [x] Update existing tests for the core() identity getter.
- [x] Complete the mappings for the renamed identity API.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | No deployment or committed logs | Covered: [test][test_givenMalformedCoreKernel_whenDeployed_reverts]; [test][test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts] |

[test_givenCoreKernelReadFails_whenDeployed_reverts]: constructor.t.sol#L196
[test_givenCoreLifecycle_whenAnyCallerDeploys]: constructor.t.sol#L105
[test_givenForeignKernel_whenDeployed_reverts]: constructor.t.sol#L209
[test_whenConstructorLifecycleSeeds]: constructor.t.sol#L241
[test_whenFacilityHasNoCode_reverts]: constructor.t.sol#L137
[test_whenZeroFacility_reverts]: constructor.t.sol#L125
[test_whenZeroOhm_reverts]: constructor.t.sol#L118

[test_givenMalformedCoreMetadata_whenDeployed_reverts]: constructor.t.sol#L224

[test_givenMissingCoreInterface_whenDeployed_reverts]: constructor.t.sol#L145

[test_givenRevertingCoreInterface_whenDeployed_reverts]: constructor.t.sol#L158

[test_givenMalformedCoreInterface_whenDeployed_reverts]: constructor.t.sol#L170

[test_givenMissingERC165_whenDeployed_reverts]: constructor.t.sol#L182

[test_givenMalformedCoreKernel_whenDeployed_reverts]: constructor.t.sol#L250

[test_givenMalformedCoreKernelBoundaries_whenDeployed_reverts]: constructor.t.sol#L267

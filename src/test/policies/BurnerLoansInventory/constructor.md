# BurnerLoansInventory.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansInventory.sol#L84). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-CONSTRUCTOR` identifies this contract/function.

Kernel,OHM,Core.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Lifecycle

Fixed for this table: Accounting / events: Immutable Core/OHM; Config=0; claims/idle/principal/cap=0; disabled; grace 7 days.

| ID | Caller | Core active | Core enabled | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-L01 | Fuzz all deployers | true | false | Other constructor inputs valid; | Success | Partial: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds]; core() getter assertion replaces the former facility() assertion |
| BLINV-CONSTRUCTOR-L02 | Fuzz all deployers | false | true | Other constructor inputs valid; | Success | Partial: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds]; core() getter assertion replaces the former facility() assertion |
| BLINV-CONSTRUCTOR-L03 | Fuzz all deployers | false | false | Other constructor inputs valid; | Success | Partial: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds]; core() getter assertion replaces the former facility() assertion |

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: No deployment or committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-D01 | Fuzz all deployers | Core deployed; reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Covered: [test_givenForeignKernel_whenDeployed_reverts][test_givenForeignKernel_whenDeployed_reverts] |

## Invalid inputs

Fixed for this table: Core active: true; Core enabled: true; Accounting / events: No deployment or committed logs.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-I01 | Fuzz all deployers | OHM=0; Core nonzero | BurnerLoansInventory_ZeroAddress() | Covered: [test_whenZeroOhm_reverts][test_whenZeroOhm_reverts] |
| BLINV-CONSTRUCTOR-I02 | Fuzz all deployers | OHM nonzero; Core=0 | BurnerLoansInventory_ZeroAddress() | Covered: [test_whenZeroFacility_reverts][test_whenZeroFacility_reverts] |
| BLINV-CONSTRUCTOR-I03 | Fuzz all deployers | Core is EOA | BurnerLoansInventory_InvalidCore(Core) | Covered: [test_whenFacilityHasNoCode_reverts][test_whenFacilityHasNoCode_reverts] |

## Successful execution

Fixed for this table: Core active: true; Core enabled: true.

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-P02 | Fuzz all deployers | Other constructor inputs valid; | Success | Immutable Core/OHM; Config=0; claims/idle/principal/cap=0; disabled; grace 7 days | Partial: [test_givenCoreLifecycle_whenAnyCallerDeploys][test_givenCoreLifecycle_whenAnyCallerDeploys]; [test_whenConstructorLifecycleSeeds][test_whenConstructorLifecycleSeeds]; core() getter assertion replaces the former facility() assertion |

## Dependency call failures

| ID | Caller | Dependency behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONSTRUCTOR-P01 | Fuzz all deployers | Core kernel getter reverts | PolicyDependency_InvalidDependency(Core) | No deployment or committed logs | Covered: [test_givenCoreKernelReadFails_whenDeployed_reverts][test_givenCoreKernelReadFails_whenDeployed_reverts] |

## Shared assertions

Constructor revert leaves no contract/state/events. Read exact zero/default fields, immutable address relationships and actual initial lifecycle/gas values, not only successful deployment. Supported interfaces and runtime budget separately verified.

Co-located API assertions: `ohm`, `core` (renamed from facility(); update the existing getter assertion when porting). These must be asserted independently of the action return value.

- [x] Review these expectations.
- [ ] Update existing tests for the core() identity getter.
- [ ] Complete the mappings for the renamed identity API.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenCoreKernelReadFails_whenDeployed_reverts]: constructor.t.sol#L135
[test_givenCoreLifecycle_whenAnyCallerDeploys]: constructor.t.sol#L98
[test_givenForeignKernel_whenDeployed_reverts]: constructor.t.sol#L148
[test_whenConstructorLifecycleSeeds]: constructor.t.sol#L163
[test_whenFacilityHasNoCode_reverts]: constructor.t.sol#L125
[test_whenZeroFacility_reverts]: constructor.t.sol#L118
[test_whenZeroOhm_reverts]: constructor.t.sol#L111

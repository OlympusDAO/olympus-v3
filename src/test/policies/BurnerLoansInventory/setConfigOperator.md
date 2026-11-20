# BurnerLoansInventory.setConfigOperator coverage plan

Source: [setConfigOperator](../../../policies/burnerloans/BurnerLoansInventory.sol#L207).

Inventory reuses `ConfigOperatorSingleStep` for operator storage, rotation, revocation, events and the unchanged-selection error. Its concrete override retains ADMIN, own-activity and Inventory/Core settlement guards. The `BLINV-CONFIGURATOR` scenario IDs remain stable through this API rename.

## Domains and notation

Scenario scope: `BLINV-CONFIGURATOR`. ADMIN_ROLE directly selects Inventory's independent recovery controller. It may call burnSurplus and rescueSurplus, not the ADMIN-only cap setter. Inventory does not inspect an upstream controller's interface, Kernel or lifecycle. Zero clears delegated recovery authority. Core and BurnerLoansConfig replacements do not synchronize this pointer. Guard order: local reentrancy, Core.requireNotReentrant, own activity, ADMIN authorization, unchanged-address rejection. Local enablement and Core lifecycle are not gates.

Unchanged includes the cap/controller, provider claims and idle, principal, OHM balances/supply, MINTR approval, Core/FLOAN positions and committed logs. `MAXn=2**n-1`.

## Authorization

Inventory active, idle guards, distinct nonzero candidate. Local enabled=true.

| ID | Caller | Request | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONFIGURATOR-A06 | ADMIN_ROLE holder | Select independent recovery controller | Success | Store exact candidate; ConfigOperatorSet(candidate); accounting unchanged | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-A05 | Fuzz caller excluding all ADMIN_ROLE holders; seed immutable Core, current recovery configurator and BL-admin-only | Distinct candidate | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts]; [test_whenControllerBoundarySeeds][test_whenControllerBoundarySeeds] |

## Local lifecycle

Use ADMIN and a changed candidate; Core guard idle and cached ROLES usable.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-CONFIGURATOR-P01 | ADMIN_ROLE holder | true | true | Success | New controller and one ConfiguratorSet; accounting unchanged | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-P02 | ADMIN_ROLE holder | true | false | Success | Same authority update while paused; remain disabled | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-L01 | ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Inventory) | Unchanged | Covered: [test_givenInactiveInventory_whenSelected_reverts][test_givenInactiveInventory_whenSelected_reverts] |
| BLINV-CONFIGURATOR-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Inventory) | Unchanged | Covered: [test_givenInactiveInventory_whenSelected_reverts][test_givenInactiveInventory_whenSelected_reverts] |

## Pointer inputs and upstream independence

Inventory active, caller ADMIN, Core idle. This is identity-based delegation; no controller API is required.

| ID | Caller | Input / transition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONFIGURATOR-A02 | ADMIN_ROLE holder | Candidate equals current nonzero address | ConfigOperator_Unchanged() | Unchanged; no event | Covered: [test_whenUnchangedController_reverts][test_whenUnchangedController_reverts]; [test_whenControllerBoundarySeeds][test_whenControllerBoundarySeeds] |
| BLINV-CONFIGURATOR-I01 | ADMIN_ROLE holder | Current pointer and candidate both zero | ConfigOperator_Unchanged() | Unchanged | Covered: [test_whenUnchangedController_reverts][test_whenUnchangedController_reverts]; [test_whenControllerBoundarySeeds][test_whenControllerBoundarySeeds] |
| BLINV-CONFIGURATOR-A03 | ADMIN_ROLE holder | Distinct contract whose interface/Kernel/lifecycle getters reject | Success without reverse reads | Store exact address; one ConfiguratorSet | Covered: [test_givenControllerWithoutUsableViews_whenSelected_succeeds][test_givenControllerWithoutUsableViews_whenSelected_succeeds] |
| BLINV-CONFIGURATOR-A04 | ADMIN_ROLE holder | Nonzero current pointer; candidate zero | Success | Clear delegated recovery authority; ConfigOperatorSet(0); ADMIN retains access | Covered: [test_givenController_whenCleared][test_givenController_whenCleared] |
| BLINV-CONFIGURATOR-P05 | ADMIN_ROLE holder | Select distinct EOA recovery configurator | Success | Store EOA; no code/interface requirement | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected]; [test_whenControllerBoundarySeeds][test_whenControllerBoundarySeeds] |
| BLINV-CONFIGURATOR-D01 | ADMIN_ROLE holder | Core Config replaced after Inventory controller installed | Inventory controller unchanged | No Inventory handoff or automatic new Config authority | Covered: [test_givenCoreControllerReplaced_whenInventoryOperatorRead_thenUnchanged][test_givenCoreControllerReplaced_whenInventoryOperatorRead_thenUnchanged] |

## Core lifecycle independence

Inventory active, local enablement independently varied; Core guard idle. Guarantee all four Core flag pairs.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-CONFIGURATOR-D02 | ADMIN_ROLE holder | true | true | Success | Controller update only | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-D03 | ADMIN_ROLE holder | true | false | Success | Controller update only | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-D04 | ADMIN_ROLE holder | false | true | Success | Controller update only | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |
| BLINV-CONFIGURATOR-D05 | ADMIN_ROLE holder | false | false | Success | Controller update only | Covered: [test_whenDistinctControllerSelected][test_whenDistinctControllerSelected] |

## Reentrancy

Use one authorized setter callback. The Core guard read also covers the incoming-transfer-before-Inventory-settlement interval.

| ID | Caller | Busy boundary / handling | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-CONFIGURATOR-C01 | ADMIN_ROLE holder | Inventory guard entered; nested setter rejection caught | Nested ReentrancyGuardReentrantCall(); outer operation can finish once | No nested controller write | Covered: [test_givenOperatorCallback_whenRejectionCaught_succeeds][test_givenOperatorCallback_whenRejectionCaught_succeeds] |
| BLINV-CONFIGURATOR-C02 | ADMIN_ROLE holder | Inventory guard entered; callback propagates rejection | ReentrancyGuardReentrantCall() | Full outer rollback | Covered: [test_givenOperatorCallback_whenRejectionPropagates_reverts][test_givenOperatorCallback_whenRejectionPropagates_reverts] |
| BLINV-CONFIGURATOR-C03 | ADMIN_ROLE holder | Core guard entered before Inventory settlement | ReentrancyGuardReentrantCall() from Core.requireNotReentrant | No controller write/event | Covered: [test_givenFeeReceiptCallback_whenOperatorRejectionCaught_succeeds][test_givenFeeReceiptCallback_whenOperatorRejectionCaught_succeeds]; [test_givenFeeReceiptCallback_whenOperatorRejectionPropagates_reverts][test_givenFeeReceiptCallback_whenOperatorRejectionPropagates_reverts] |

- [ ] Review expectations and implement ADMIN-driven controller tests.
- [ ] Update Test mappings when proved.

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenControllerWithoutUsableViews_whenSelected_succeeds]: setConfigOperator.t.sol#L40
[test_givenController_whenCleared]: setConfigOperator.t.sol#L47
[test_givenCoreControllerReplaced_whenInventoryOperatorRead_thenUnchanged]: setConfigOperatorIntegration.t.sol#L20
[test_givenFeeReceiptCallback_whenOperatorRejectionCaught_succeeds]: setConfigOperatorIntegration.t.sol#L33
[test_givenFeeReceiptCallback_whenOperatorRejectionPropagates_reverts]: setConfigOperatorIntegration.t.sol#L46
[test_givenInactiveInventory_whenSelected_reverts]: setConfigOperator.t.sol#L88
[test_givenOperatorCallback_whenRejectionCaught_succeeds]: setConfigOperatorCallback.t.sol#L18
[test_givenOperatorCallback_whenRejectionPropagates_reverts]: setConfigOperatorCallback.t.sol#L34
[test_whenControllerBoundarySeeds]: setConfigOperator.t.sol#L102
[test_whenDistinctControllerSelected]: setConfigOperator.t.sol#L19
[test_whenUnauthorizedCaller_reverts]: setConfigOperator.t.sol#L77
[test_whenUnchangedController_reverts]: setConfigOperator.t.sol#L62

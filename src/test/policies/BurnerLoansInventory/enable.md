# BurnerLoansInventory.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive. The Core address is an authorization reference: Core activity and local enablement are not Inventory activation requirements; Core validates Inventory compatibility when selecting and activating its services.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Core is an immutable identity and settlement-guard reference, not an enabled-only funding dependency. Validate the immutable Core interface and matching Kernel without requiring Core activity or enablement. Core owns admission of Inventory through setInventory, enable and reEnable. Validate own Kernel membership and resolve MINTR/ROLES/TRSRY through the Kernel; no controller lifecycle gate or activation cycle.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansInventory_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test_givenNoConfigurator_succeeds][test_givenNoConfigurator_succeeds] |
| BLINV-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test_whenCallerIsUnauthorized_reverts][test_whenCallerIsUnauthorized_reverts] |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLINV-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Covered: [test_whenPayloadIsNonempty_reverts][test_whenPayloadIsNonempty_reverts]; [test_whenPayloadBoundarySeeds_revert][test_whenPayloadBoundarySeeds_revert] |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test_givenAlreadyEnabled_whenEnabled_reverts][test_givenAlreadyEnabled_whenEnabled_reverts] |
| BLINV-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test_whenCallerIsUnauthorized_reverts][test_whenCallerIsUnauthorized_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | NotDisabled() | Unchanged; local transition state rejects before caller, payload and hooks | Covered: [test_givenAlreadyEnabled_whenEnabled_reverts][test_givenAlreadyEnabled_whenEnabled_reverts] |

## Dependency lifecycle

Local enabled=false; data=0x; ROLES initialized. The immutable Inventory is locally disabled and Kernel-active; Core is the immutable authority; its interface and matching Kernel are validated. Core active/enabled flags do not gate provider operations. Change only the named reference condition. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-D01 | ADMIN_ROLE holder | Core | false | true | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenFacilityLifecycle_whenEnabled][test_givenFacilityLifecycle_whenEnabled]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-ENABLE-D02 | ADMIN_ROLE holder | Core | true | false | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenFacilityLifecycle_whenEnabled][test_givenFacilityLifecycle_whenEnabled]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |
| BLINV-ENABLE-D03 | ADMIN_ROLE holder | Core | false | false | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenFacilityLifecycle_whenEnabled][test_givenFacilityLifecycle_whenEnabled]; [test_whenCoreLifecycleSeeds][test_whenCoreLifecycleSeeds] |

## Dependency compatibility

Local enabled=false; data=0x; ROLES initialized. The immutable Inventory is locally disabled and Kernel-active; Core is the immutable authority; its interface and matching Kernel are validated. Core active/enabled flags do not gate provider operations. Change only the named reference condition. Dependency lifecycle otherwise satisfies the listed defaults.

| ID | Caller | Component | Binding / interface fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-D04 | ADMIN_ROLE holder | Core | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenFacilityReportsDifferentKernel_whenEnabled_revertsThenRestored][test_givenFacilityReportsDifferentKernel_whenEnabled_revertsThenRestored] |

## Local activity

Local enabled=false; data=0x; ROLES initialized. The immutable Inventory is locally disabled and Kernel-active; Core is the immutable authority; its interface and matching Kernel are validated. Core active/enabled flags do not gate provider operations. Change only the named reference condition. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenInactiveInventory_whenEnabled_reverts][test_givenInactiveInventory_whenEnabled_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test_givenUnconfiguredInventory_whenEnabled_reverts][test_givenUnconfiguredInventory_whenEnabled_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

## Core compatibility and readiness

| ID | Caller | Core metadata | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-ENABLE-D05 | ADMIN | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | Paused state, history and accounting preserved; restoration permits retry | Covered: [test][test_givenUnreadableCoreMetadata_whenEnabled_revertsThenRestored] |

## Callable Core compatibility

Construction and activation share the same IBurnerLoansCore interface validator. Core must report the same Kernel; its activity and local enablement remain independent. Existing payload, settlement, own-policy and caller guards retain their order.

| ID | Core condition | Result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLINV-ENABLE-D06 | Missing IBurnerLoansCore support | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLINV-ENABLE-D07 | Interface probe reverts | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_reverts] |
| BLINV-ENABLE-D08 | Interface probe returns short data | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_reverts] |

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLINV-ENABLE-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]; [test][test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored] |
| BLINV-ENABLE-K04 | Core migrates while old Kernel retains active membership; pause remains available | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenCoreMigrated_whenActivated_revertsThenRestored] |

[test_givenAlreadyEnabled_whenEnabled_reverts]: enable.t.sol#L122
[test_givenFacilityLifecycle_whenEnabled]: enable.t.sol#L42
[test_givenFacilityReportsDifferentKernel_whenEnabled_revertsThenRestored]: enable.t.sol#L50
[test_givenInactiveInventory_whenEnabled_reverts]: enable.t.sol#L80
[test_givenNoConfigurator_succeeds]: enable.t.sol#L27
[test_givenUnconfiguredInventory_whenEnabled_reverts]: enable.t.sol#L136
[test_whenCallerIsUnauthorized_reverts]: enable.t.sol#L92
[test_whenCoreLifecycleSeeds]: enable.t.sol#L147
[test_whenPayloadBoundarySeeds_revert]: enable.t.sol#L112
[test_whenPayloadIsNonempty_reverts]: enable.t.sol#L102

[test_givenUnreadableCoreMetadata_whenEnabled_revertsThenRestored]: enable.t.sol#L65

[test_givenMissingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L156

[test_givenRevertingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L181

[test_givenMalformedCoreInterface_whenActivated_reverts]: ./enable.t.sol#L209

[test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L246

[test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored]: enable.t.sol#L262

[test_givenCoreMigrated_whenActivated_revertsThenRestored]: enable.t.sol#L287

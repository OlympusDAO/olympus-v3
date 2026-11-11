# BurnerLoansInventory.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope: `BLINV-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive. The Core address is an authorization reference: Core activity and local enablement are not Inventory activation requirements; Core validates Inventory compatibility when selecting and activating its services.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

Core must expose the expected interface and report the same Kernel; its activity and enablement do not gate Inventory. Inventory itself must be Kernel-active; Core activity is not checked. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Core is an immutable identity and settlement-guard reference, not an enabled-only funding dependency. Validate the immutable Core interface and matching Kernel without requiring Core activity or enablement. Core owns admission of Inventory through setInventory, enable and reEnable. Validate own Kernel membership and resolve MINTR/ROLES/TRSRY through the Kernel; no controller lifecycle gate or activation cycle.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansInventory_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts] |
| BLINV-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test_givenUnrepresentableDeadline_whenReEnabled_reverts][test_givenUnrepresentableDeadline_whenReEnabled_reverts]; [test_whenGraceAndRoleBoundarySeeds][test_whenGraceAndRoleBoundarySeeds] |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | NotDisabled() | Unchanged; before authorization and hook reads | Covered: [test_givenAlreadyEnabled_whenReEnabled_reverts][test_givenAlreadyEnabled_whenReEnabled_reverts] |
| BLINV-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | NeverEnabled() | Unchanged; before authorization and hook reads | Covered: [test_givenConfiguredNeverEnabled_whenReEnabled_reverts][test_givenConfiguredNeverEnabled_whenReEnabled_reverts] |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. Core must expose the expected interface and report the same Kernel; its activity and enablement do not gate Inventory. Inventory itself must be Kernel-active; Core activity is not checked. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Covered: [test_givenValidGrace_whenReEnabled][test_givenValidGrace_whenReEnabled]; [test_whenGraceAndRoleBoundarySeeds][test_whenGraceAndRoleBoundarySeeds] |
| BLINV-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Covered: [test_givenValidGrace_whenReEnabled][test_givenValidGrace_whenReEnabled]; [test_whenGraceAndRoleBoundarySeeds][test_whenGraceAndRoleBoundarySeeds] |
| BLINV-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Covered: [test_givenExpiredGrace_whenReEnabled_reverts][test_givenExpiredGrace_whenReEnabled_reverts]; [test_whenGraceAndRoleBoundarySeeds][test_whenGraceAndRoleBoundarySeeds] |

## Dependency lifecycle

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must expose the expected interface and report the same Kernel; its activity and enablement do not gate Inventory. Inventory itself must be Kernel-active; Core activity is not checked. Fuzz both permitted role classes through every enable prerequisite. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | false | true | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenDependencyLifecycle_whenReEnabled][test_givenDependencyLifecycle_whenReEnabled]; [test_whenDependencyAndRoleBoundarySeeds][test_whenDependencyAndRoleBoundarySeeds] |
| BLINV-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | true | false | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenDependencyLifecycle_whenReEnabled][test_givenDependencyLifecycle_whenReEnabled]; [test_whenDependencyAndRoleBoundarySeeds][test_whenDependencyAndRoleBoundarySeeds] |
| BLINV-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | false | false | Success; Core reference binding valid; no Core-state dependency | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenDependencyLifecycle_whenReEnabled][test_givenDependencyLifecycle_whenReEnabled]; [test_whenDependencyAndRoleBoundarySeeds][test_whenDependencyAndRoleBoundarySeeds] |

## Dependency compatibility

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must expose the expected interface and report the same Kernel; its activity and enablement do not gate Inventory. Inventory itself must be Kernel-active; Core activity is not checked. Fuzz both permitted role classes through every enable prerequisite. Dependency lifecycle otherwise satisfies the listed defaults.

| ID | Caller | Component | Binding / interface fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenForeignCoreKernel_whenReEnabled_revertsThenRestored][test_givenForeignCoreKernel_whenReEnabled_revertsThenRestored]; [test_whenDependencyAndRoleBoundarySeeds][test_whenDependencyAndRoleBoundarySeeds] |

## Local activity

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must expose the expected interface and report the same Kernel; its activity and enablement do not gate Inventory. Inventory itself must be Kernel-active; Core activity is not checked. Fuzz both permitted role classes through every enable prerequisite. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenInactiveInventory_whenReEnabled_reverts][test_givenInactiveInventory_whenReEnabled_reverts]; [test_whenDependencyAndRoleBoundarySeeds][test_whenDependencyAndRoleBoundarySeeds] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverConfigured_whenReEnabled_reverts][test_givenNeverConfigured_whenReEnabled_reverts] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

## Core compatibility and readiness

| ID | Caller | Core metadata | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINV-REENABLE-D05 | ADMIN | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | Paused state, history and accounting preserved; restoration permits retry | Covered: [test][test_givenUnreadableCoreMetadata_whenReEnabled_revertsThenRestored] |

## Callable Core compatibility

Construction and activation share the same IBurnerLoansCore interface validator. Core must report the same Kernel; its activity and local enablement remain independent. Existing payload, settlement, own-policy and caller guards retain their order.

| ID | Core condition | Result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLINV-REENABLE-D06 | Missing IBurnerLoansCore support | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLINV-REENABLE-D07 | Interface probe reverts | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_reverts] |
| BLINV-REENABLE-D08 | Interface probe returns short data | BurnerLoansInventory_InvalidCore(Core) | Paused state and timestamp preserved; restoring support permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_reverts] |

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLINV-REENABLE-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]; [test][test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored] |
| BLINV-REENABLE-K04 | Core migrates while old Kernel retains active membership; pause remains available | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenCoreMigrated_whenActivated_revertsThenRestored] |

[test_givenAlreadyEnabled_whenReEnabled_reverts]: reEnable.t.sol#L244
[test_givenConfiguredNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L229
[test_givenDependencyLifecycle_whenReEnabled]: reEnable.t.sol#L130
[test_givenExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L81
[test_givenForeignCoreKernel_whenReEnabled_revertsThenRestored]: reEnable.t.sol#L147
[test_givenInactiveInventory_whenReEnabled_reverts]: reEnable.t.sol#L188
[test_givenNeverConfigured_whenReEnabled_reverts]: reEnable.t.sol#L238
[test_givenUnrepresentableDeadline_whenReEnabled_reverts]: reEnable.t.sol#L106
[test_givenValidGrace_whenReEnabled]: reEnable.t.sol#L63
[test_whenDependencyAndRoleBoundarySeeds]: reEnable.t.sol#L299
[test_whenGraceAndRoleBoundarySeeds]: reEnable.t.sol#L259
[test_whenUnauthorizedCaller_reverts]: reEnable.t.sol#L207

[test_givenUnreadableCoreMetadata_whenReEnabled_revertsThenRestored]: reEnable.t.sol#L171

[test_givenMissingCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L336

[test_givenRevertingCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L362

[test_givenMalformedCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L391

[test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]: reEnable.t.sol#L429

[test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored]: reEnable.t.sol#L447

[test_givenCoreMigrated_whenActivated_revertsThenRestored]: reEnable.t.sol#L474

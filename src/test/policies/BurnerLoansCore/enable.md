# BurnerLoansCore.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then payload length, then the settlement guard and enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Check selected Inventory, Payout and Risk as required Core-bound services: required interfaces, canonical core()=this Core, reported Kernel identity, authoritative membership in this Kernel, then enabled state. DepositManager is a required same-Kernel Policy service with no Core binding. Config, actions and Lens are not Core activation dependencies.

Keep enable and reEnable on the same compatibility/readiness predicates. Core uses `PolicyDependency_KernelMismatch(dependency,expectedKernel,reportedKernel)` for readable foreign-Kernel metadata. Unset or otherwise invalid dependencies use their component-specific `InvalidDependency(candidate)` error; compatible selected services that become inactive or disabled use `PolicyDependency_NotActive(dependency)`. These Core-specific error choices take precedence over the general [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Unset pointers, missing interfaces and incompatible Core bindings use component errors; failed/malformed Kernel/status reads use `PolicyDependency_InvalidDependency(dependency)`. Component error ownership: DepositManager → `BurnerLoansCore_InvalidDepositManager(DepositManager)`; Inventory → `BurnerLoansCore_InvalidInventory(Inventory)`; Payout → `BurnerLoansCore_InvalidPayout(Payout)`; Risk → `BurnerLoansCore_InvalidRisk(Risk)`.

## Authorization

Fixed for this table: Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test][test_givenReadyGraph_whenEnabled] |
| BLCORE-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test][test_givenUnauthorized_whenEnabled_reverts] |

## Inputs and guard precedence

ROLES initialized; ADMIN and Local enabled=false unless the row varies them. Dependencies are ready. Fuzz nonempty payload length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes. Every nonzero length is invalid. The successful authorization case proves empty-data acceptance.

| ID | Caller | Payload / competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Unchanged; no lifecycle/token logs | Covered: [test][test_givenPayload_whenEnabled_reverts] |
| BLCORE-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; no lifecycle/token logs | Covered: [test][test_givenEnabledCoreAndPayload_whenEnabled_reverts] |
| BLCORE-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no lifecycle/token logs | Covered: [test][test_givenUnauthorizedAndPayload_whenEnabled_reverts] |
| BLCORE-ENABLE-I04 | ADMIN_ROLE holder | Nonempty bytes; valid transition state; Core guard entered | `BurnerLoans_InvalidEnablerData()` | Unchanged; no lifecycle/token logs | Covered: [test][test_givenBusyCoreAndPayload_whenEnabled_reverts] |

## Local transition state

ROLES initialized. Data=0x for enable; for reEnable, L>0 and a representable unexpired grace deadline unless the row states otherwise. The own enabled-state check precedes authorization; own activity is checked before operational dependencies.

| ID | Caller | Local active | Local enabled | History | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Any reachable history | NotDisabled() | Unchanged; before authorization and hooks | Covered: [test][test_givenAlreadyEnabled_whenEnabled_reverts] |
| BLCORE-ENABLE-L02 | Fuzz ADMIN_ROLE holder | false | false | Previously activated; ROLES retained | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Unchanged; no committed logs | Covered: [test][test_givenCoreInactive_whenEnabled_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverConfigured_whenEnabled_reverts] |

## Dependency lifecycle

Local active=true; Local enabled=false; initialized ROLES; authorized caller; Core guard idle; data=0x for enable, valid history/grace for reEnable. DepositManager, Inventory, Payout and Risk must be active in Core’s Kernel, report that Kernel and be locally enabled. Inventory, Payout and Risk have the selected Core binding; DepositManager is shared and has no Core binding. Other services stay ready.

Seed a live position and pending payout. After each failure, restore only the failed flag and retry successfully; preserve loans, balances and obligations. An inactive candidate that falsely reports Core’s Kernel still fails the authoritative `kernel.isPolicyActive(candidate)` lookup. Successful authorization/timing cases cover all services ready.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects / recovery | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-D01 | Fuzz ADMIN_ROLE holder | DepositManager | false | true | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D02 | Fuzz ADMIN_ROLE holder | DepositManager | true | false | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D03 | Fuzz ADMIN_ROLE holder | DepositManager | false | false | PolicyDependency_NotActive(DepositManager) | Unchanged; restore failed flag and retry | Covered: [test][test_givenDepositManagerUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D04 | Fuzz ADMIN_ROLE holder | Inventory | false | true | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D05 | Fuzz ADMIN_ROLE holder | Inventory | true | false | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D06 | Fuzz ADMIN_ROLE holder | Inventory | false | false | PolicyDependency_NotActive(Inventory) | Unchanged; restore failed flag and retry | Covered: [test][test_givenInventoryUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D07 | Fuzz ADMIN_ROLE holder | Payout | false | true | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D24 | Fuzz ADMIN_ROLE holder | Payout | true | false | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D26 | Fuzz ADMIN_ROLE holder | Payout | false | false | PolicyDependency_NotActive(Payout) | Unchanged; restore failed flag and retry | Covered: [test][test_givenPayoutUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D20 | Fuzz ADMIN_ROLE holder | Risk | true | false | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D21 | Fuzz ADMIN_ROLE holder | Risk | false | true | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |
| BLCORE-ENABLE-D22 | Fuzz ADMIN_ROLE holder | Risk | false | false | PolicyDependency_NotActive(Risk) | Unchanged; restore failed flag and retry | Covered: [test][test_givenRiskUnavailable_whenEnabled_reverts] |

## Dependency compatibility

Core active and locally disabled; other prerequisites pass. Use reachable pre-link setup for missing pointers. For reported-Kernel drift, keep membership in Core’s Kernel and vary only the reported Kernel, for example after dependency Kernel migration. Interface and immutable Core-binding failures belong to pointer-installation tests; do not erase validated code to create unreachable activation inputs. Config is not inspected.

| ID | Caller | Dependency | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-D08 | Fuzz ADMIN_ROLE holder | DepositManager | Reports another Kernel | PolicyDependency_KernelMismatch(DepositManager,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenDepositManagerWrongKernel_whenEnabled_reverts] |
| BLCORE-ENABLE-D09 | Fuzz ADMIN_ROLE holder | Inventory | Reports another Kernel | PolicyDependency_KernelMismatch(Inventory,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenInventoryWrongKernel_whenEnabled_reverts] |
| BLCORE-ENABLE-D10 | Fuzz ADMIN_ROLE holder | Payout | Reports another Kernel | PolicyDependency_KernelMismatch(Payout,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_givenPayoutWrongKernel_whenEnabled_reverts] |
| BLCORE-ENABLE-D11 | Fuzz ADMIN_ROLE holder | Risk | Selected address zero | BurnerLoansCore_InvalidRisk(0) | Unchanged | Covered: [test][test_givenRiskUnset_whenEnabled_reverts] |
| BLCORE-ENABLE-D32 | Fuzz ADMIN_ROLE holder | Risk | Reports another Kernel | PolicyDependency_KernelMismatch(Risk,expectedKernel,reportedKernel) | No transition or accounting/log change | Covered: [test][test_givenRiskWrongKernel_whenEnabled_reverts] |
| BLCORE-ENABLE-D33 | Fuzz ADMIN_ROLE holder | Inventory | Unset address zero | BurnerLoansCore_InvalidInventory(0) | No transition or accounting/log change | Covered: [test][test_givenInventoryUnset_whenEnabled_reverts] |
| BLCORE-ENABLE-D34 | Fuzz ADMIN_ROLE holder | Payout | Unset address zero | BurnerLoansCore_InvalidPayout(0) | No transition or accounting/log change | Covered: [test][test_givenPayoutUnset_whenEnabled_reverts] |

## Upstream Config independence

Core active and locally disabled; downstream services ready; selected Config address retained. Config is an upstream authority, not an operational dependency. Guarantee all four Config flag pairs.

| ID | Caller | Config active | Config enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-D14 | Fuzz ADMIN_ROLE holder | Fuzz false/true | Fuzz false/true | Success | Normal transition; no Config lifecycle getter | Covered: [test][test_givenConfigUnavailable_whenEnabled] |
| BLCORE-ENABLE-D18 | Fuzz ADMIN_ROLE holder | Fuzz false/true | Fuzz false/true | Success even if Config reports another Kernel | No Config Kernel/interface getter; upstream installation owns correctness | Covered: [test][test_givenConfigUnavailable_whenEnabled] |

## Callbacks and reentrancy

An authorized callback calls enable during Core.rescue while Core is disabled. Other admission conditions pass; use the permitted caller family above.

| ID | Caller | Nested call handling | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-ENABLE-C01 | Fuzz ADMIN_ROLE holder (callback contract) | Catch nested rejection | ReentrancyGuardReentrantCall() | Outer rescue completes once; no lifecycle transition | Covered: [test][test_givenBusyCore_whenCaughtEnable_reverts] |
| BLCORE-ENABLE-C02 | Fuzz ADMIN_ROLE holder (callback contract) | Propagate nested rejection | ReentrancyGuardReentrantCall() | Outer rescue and lifecycle mutation roll back; no committed logs | Covered: [test][test_givenBusyCore_whenPropagatedEnable_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

[test_givenAlreadyEnabled_whenEnabled_reverts]: enable.t.sol#L57
[test_givenBusyCoreAndPayload_whenEnabled_reverts]: enable.t.sol#L398
[test_givenBusyCore_whenCaughtEnable_reverts]: enable.t.sol#L340
[test_givenBusyCore_whenPropagatedEnable_reverts]: enable.t.sol#L359
[test_givenConfigUnavailable_whenEnabled]: enable.t.sol#L317
[test_givenCoreInactive_whenEnabled_reverts]: enable.t.sol#L65
[test_givenDepositManagerUnavailable_whenEnabled_reverts]: enable.t.sol#L81
[test_givenDepositManagerWrongKernel_whenEnabled_reverts]: enable.t.sol#L113
[test_givenEnabledCoreAndPayload_whenEnabled_reverts]: enable.t.sol#L383
[test_givenInventoryUnavailable_whenEnabled_reverts]: enable.t.sol#L129
[test_givenInventoryUnset_whenEnabled_reverts]: enable.t.sol#L281
[test_givenInventoryWrongKernel_whenEnabled_reverts]: enable.t.sol#L161
[test_givenNeverConfigured_whenEnabled_reverts]: enable.t.sol#L413
[test_givenPayload_whenEnabled_reverts]: enable.t.sol#L374
[test_givenPayoutUnavailable_whenEnabled_reverts]: enable.t.sol#L177
[test_givenPayoutUnset_whenEnabled_reverts]: enable.t.sol#L299
[test_givenPayoutWrongKernel_whenEnabled_reverts]: enable.t.sol#L209
[test_givenReadyGraph_whenEnabled]: enable.t.sol#L28
[test_givenRiskUnavailable_whenEnabled_reverts]: enable.t.sol#L221
[test_givenRiskUnset_whenEnabled_reverts]: enable.t.sol#L265
[test_givenRiskWrongKernel_whenEnabled_reverts]: enable.t.sol#L253
[test_givenUnauthorizedAndPayload_whenEnabled_reverts]: enable.t.sol#L389
[test_givenUnauthorized_whenEnabled_reverts]: enable.t.sol#L46

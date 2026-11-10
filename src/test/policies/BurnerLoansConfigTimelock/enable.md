# BurnerLoansConfigTimelock.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column.

Coverage records implemented scenario domains and assertions. Execution results are recorded separately from coverage.

## Domains and notation

Scenario scope: `BLCT-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

The immutable Config target is a required same-Kernel active Policy (local enablement is not required for activation) that selects this timelock as its configOperator. Config owns its relationship with Core; the timelock does not revalidate Core’s Config selection. Target authority matching is separate from readiness. Risk is checked only for Risk-targeted proposals; no global Risk-operator equality or recursive Core/Inventory readiness gate is introduced.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: invalid Config metadata → `BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config)`; a readable Config Kernel different from this timelock’s Kernel → `PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel)`. This distinct Kernel-mismatch rule applies to both enable and reEnable. Missing validation/error-name changes remain implementation work.

## Authorization

Fixed for this table: Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test_givenAdmin_whenEnabled_thenExactTransition][test_givenAdmin_whenEnabled_thenExactTransition] |
| BLCT-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test_givenNonAdmin_whenEnabled_reverts][test_givenNonAdmin_whenEnabled_reverts] |

## Inputs

Fixed for this table: Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCT-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Covered: [test_givenAdmin_whenNonemptyData_reverts][test_givenAdmin_whenNonemptyData_reverts]; [test_givenEnableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenEnableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds] |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test_givenEnabled_whenNonemptyEnableData_thenStateError][test_givenEnabled_whenNonemptyEnableData_thenStateError]; [test_givenEnableI02Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenEnableI02Payloads_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test_givenNonAdmin_whenNonemptyData_thenRoleError][test_givenNonAdmin_whenNonemptyData_thenRoleError]; [test_givenEnableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds][test_givenEnableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Local transition state

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | NotDisabled() | Unchanged; local transition state rejects before caller, payload and hooks | Covered: [test_givenAlreadyEnabled_whenEnableCalled_thenStateError][test_givenAlreadyEnabled_whenEnableCalled_thenStateError] |

## Dependency lifecycle

Local enabled=false; data=0x; ROLES initialized. The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. Change only the condition named in each row. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-D01 | ADMIN_ROLE holder | Config | false | true | PolicyDependency_NotActive(Config) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenConfigActiveFalse_givenConfigEnabledTrue_whenEnable_reverts][test_givenConfigActiveFalse_givenConfigEnabledTrue_whenEnable_reverts] |
| BLCT-ENABLE-D02 | ADMIN_ROLE holder | Config | true | false | Success | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenConfigActiveTrue_givenConfigEnabledFalse_whenEnable_thenEnabled][test_givenConfigActiveTrue_givenConfigEnabledFalse_whenEnable_thenEnabled] |
| BLCT-ENABLE-D03 | ADMIN_ROLE holder | Config | false | false | PolicyDependency_NotActive(Config) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test_givenConfigActiveFalse_givenConfigEnabledFalse_whenEnable_reverts][test_givenConfigActiveFalse_givenConfigEnabledFalse_whenEnable_reverts] |

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-D04 | ADMIN_ROLE holder | Config Kernel differs | PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Covered: [test_givenForeignConfigKernel_whenEnable_reverts][test_givenForeignConfigKernel_whenEnable_reverts] |

Retired: `BLCT-ENABLE-D05`.

## Local activity

Local enabled=false; data=0x; ROLES initialized. The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. Change only the condition named in each row. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenOwnPolicyInactive_whenEnable_reverts][test_givenOwnPolicyInactive_whenEnable_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverActivated_whenEnabled_thenUnsetRolesCallReverts][test_givenNeverActivated_whenEnabled_thenUnsetRolesCallReverts] |

## Independent optional Risk authority

This timelock may serve market configuration, direct Risk cache-age configuration, or both. Keep the existing Config activation requirements; activation does not require Risk to delegate its configuration authority to BLCT. Risk-targeted queue/execution performs its own readiness, same-Kernel and selected-operator checks; market-only operation remains possible when Risk uses another controller.

| ID | Caller | Risk operator | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-D06 | ADMIN_ROLE holder | Zero or controller distinct from Core Config and BLCT; guarantee both | Success with existing local/history/Config prerequisites satisfied | Normal local transition; Risk authority/cache/oracle/age untouched; no equality requirement | Covered: [test_givenRiskOperatorIndependent_whenEnable_thenEnabled][test_givenRiskOperatorIndependent_whenEnable_thenEnabled] |

## Activation compatibility

Activation and reactivation require compatible target, ConfigOperator and Enabler interfaces, same Kernel, target Policy activity and this queue selected as configOperator. They do not read the target's enabled status. This allows queue repair while the target remains paused; each queued operation still enforces its own execution requirements. Other transition/caller/history/grace/payload guards retain their existing order.

Caller is authorized and every prerequisite not varied below is valid. An incompatible target leaves lifecycle history, pending actions, reservations, configuration and custody unchanged.

| ID | Target active | Target enabled | Input fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-ENABLE-D07 | true | Fuzz false/true | Reject each consumed interface advertisement; seed every interface | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Unchanged | Covered: [test][test_givenMissingConsumedInterface_whenActivated_reverts] |

## Core compatibility revalidation

The same compatibility predicate runs at construction, enable and reEnable. The consumer is active and paused, its caller is ADMIN, and all other prerequisites pass. Core Kernel metadata, membership and local enablement are not admission requirements here.

| ID | Fault or state | Result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLCT-ENABLE-D12 | Core lacks IBurnerLoansCore | BurnerLoansConfigTimelock_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLCT-ENABLE-D13 | Core interface probe reverts | BurnerLoansConfigTimelock_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_reverts] |
| BLCT-ENABLE-D14 | Core interface probe returns short data | BurnerLoansConfigTimelock_InvalidCore(Core) | Remain paused; timestamp unchanged; restoring the interface permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_reverts] |
| BLCT-ENABLE-D15 | Config.facility() reverts | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Remain paused; timestamp unchanged; restoring the binding permits retry | Covered: [test][test_givenRevertingCoreBinding_whenActivated_reverts] |
| BLCT-ENABLE-D16 | Config.facility() returns short data | BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config) | Remain paused; timestamp unchanged; restoring the binding permits retry | Covered: [test][test_givenMalformedCoreBinding_whenActivated_reverts] |
| BLCT-ENABLE-P10 | Compatible Core; active/enabled flags independently false/true; all four seeded | Success | Consumer becomes enabled | Covered: [test][test_givenCoreLifecycle_whenActivated]; [seeds][test_whenCoreLifecycleStatesSeeded_thenActivated] |

[test_givenAdmin_whenEnabled_thenExactTransition]: enable.t.sol#L128
[test_givenNonAdmin_whenEnabled_reverts]: enable.t.sol#L141
[test_givenAdmin_whenNonemptyData_reverts]: enable.t.sol#L152
[test_givenEnableI01Payloads_whenBoundarySeedsRun_thenScenarioHolds]: enable.t.sol#L213
[test_givenEnabled_whenNonemptyEnableData_thenStateError]: enable.t.sol#L164
[test_givenEnableI02Payloads_whenBoundarySeedsRun_thenScenarioHolds]: enable.t.sol#L226
[test_givenNonAdmin_whenNonemptyData_thenRoleError]: enable.t.sol#L177
[test_givenEnableI03Payloads_whenBoundarySeedsRun_thenScenarioHolds]: enable.t.sol#L242
[test_givenAlreadyEnabled_whenEnableCalled_thenStateError]: enable.t.sol#L192
[test_givenConfigActiveFalse_givenConfigEnabledTrue_whenEnable_reverts]: enable.t.sol#L28
[test_givenConfigActiveTrue_givenConfigEnabledFalse_whenEnable_thenEnabled]: enable.t.sol#L45
[test_givenConfigActiveFalse_givenConfigEnabledFalse_whenEnable_reverts]: enable.t.sol#L61
[test_givenForeignConfigKernel_whenEnable_reverts]: enable.t.sol#L78
[test_givenOwnPolicyInactive_whenEnable_reverts]: enable.t.sol#L100
[test_givenNeverActivated_whenEnabled_thenUnsetRolesCallReverts]: enable.t.sol#L205
[test_givenRiskOperatorIndependent_whenEnable_thenEnabled]: enable.t.sol#L114

[test_givenMissingConsumedInterface_whenActivated_reverts]: enable.t.sol#L255

[test_givenMissingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L288

[test_givenRevertingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L311

[test_givenMalformedCoreInterface_whenActivated_reverts]: ./enable.t.sol#L338

[test_givenRevertingCoreBinding_whenActivated_reverts]: ./enable.t.sol#L361

[test_givenMalformedCoreBinding_whenActivated_reverts]: ./enable.t.sol#L387

[test_givenCoreLifecycle_whenActivated]: ./enable.t.sol#L409
[test_whenCoreLifecycleStatesSeeded_thenActivated]: ./enable.t.sol#L420

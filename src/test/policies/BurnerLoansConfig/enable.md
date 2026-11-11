# BurnerLoansConfig.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLCFG-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive. Core is the direct operational activation dependency and must be active and enabled; Inventory lifecycle does not gate Config activation.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Core is Config’s direct activation dependency: required interfaces, expected OHM/Kernel and active/enabled membership. Its selected Config authority must still match this contract. Inventory is not a direct dependency. Risk-specific calls validate the selected Risk when used; ordinary FLOAN-only parameter writes keep their approved independence from Core enablement.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansConfig_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test][test_givenAdmin_whenEnabled] |
| BLCFG-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCFG-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Covered: [test][test_whenEnablePayloadIsNonempty_reverts], [test][test_whenNonemptyPayloadBoundariesSeeded_reverts] |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenAlreadyEnabled_whenActivationRetried_reverts], [test][test_givenEnabled_whenNonemptyEnablePayloadSubmitted_reverts] |
| BLCFG-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Dependency lifecycle-view failures

Local active=true; local enabled=false; compatible active dependencies and interfaces. Other dependency views succeed. For reEnable, use initialized history and valid grace. A false isEnabled result is already covered in Dependency lifecycle; the cases below test a failed or undecodable call.

| ID | Caller | Dependency | Lifecycle-view behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-D01 | ADMIN_ROLE holder | Core | Mock isEnabled reverts with MockPolicyEnablerV2.MockBeforeEnableReverted() | PolicyDependency_InvalidDependency(Core) | Unchanged; no committed logs | Covered: [test][test_givenRevertingEnabled_whenActivated_reverts] |
| BLCFG-ENABLE-D02 | ADMIN_ROLE holder | Core | Mock isEnabled returns 0x01, not an ABI-encoded bool | PolicyDependency_InvalidDependency(Core) | Unchanged; no committed logs | Covered: [test][test_givenMalformedEnabled_whenActivated_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | NotDisabled() | Unchanged; local transition state rejects before caller, payload and hooks | Covered: [test][test_givenAlreadyEnabled_whenActivationRetried_reverts] |

## Dependency lifecycle

For policy-service dependencies, active means membership in this consumer’s Kernel via `kernel.isPolicyActive(dependency)`, separately from a matching reported kernel(). Inactive-dependency cases retain a matching reported Kernel to prove that self-reporting alone cannot pass. A bound action or helper must report the consumer’s expected Core through core(); shared services such as DepositManager have no invented Core binding. Constructor identity binding may precede activation.

Local enabled=false; data=0x; ROLES initialized. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Change only the condition named in each row. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-D05 | ADMIN_ROLE holder | Core | false | true | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenCoreInactiveEnabled_whenActivated_reverts] |
| BLCFG-ENABLE-D07 | ADMIN_ROLE holder | Core | true | false | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenCoreActiveDisabled_whenActivated_reverts] |
| BLCFG-ENABLE-D09 | ADMIN_ROLE holder | Core | false | false | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenCoreInactiveDisabled_whenActivated_reverts] |

## Dependency compatibility

A canonical Core kernel() read reporting another Kernel uses PolicyDependency_KernelMismatch(Core,ConfigKernel,reportedKernel), with ConfigKernel equal to this Config’s Kernel. Failed/malformed Kernel/status reads use PolicyDependency_InvalidDependency(Core); other incompatible Core identity/selection faults retain BurnerLoansConfig_InvalidCore(Core). Apply this error distinction identically in enable and reEnable.

Local enabled=false; data=0x; ROLES initialized. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Change only the condition named in each row. Dependency lifecycle otherwise satisfies the listed defaults.

| ID | Caller | Component | Binding / interface fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-D11 | ADMIN_ROLE holder | Core | Core reports another Kernel | `PolicyDependency_KernelMismatch(Core,ConfigKernel,reportedKernel)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenWrongKernel_whenActivated_reverts] |
| BLCFG-ENABLE-D12 | ADMIN_ROLE holder | Core | Core lacks IBurnerLoansCore | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLCFG-ENABLE-D13 | ADMIN_ROLE holder | Core | Core lacks IEnabler | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenMissingEnabler_whenActivated_reverts] |
| BLCFG-ENABLE-D14 | ADMIN_ROLE holder | Core | Core reports different OHM | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenDifferentOhm_whenActivated_reverts] |
| BLCFG-ENABLE-D15 | ADMIN_ROLE holder | Core | Core selects another Config | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenDifferentConfigurator_whenActivated_reverts] |

## Local activity

Local enabled=false; data=0x; ROLES initialized. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Change only the condition named in each row. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactivePolicy_whenActivated_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test][test_givenFreshPolicyWithoutRoles_whenEnabled_reverts] |

## Direct dependency boundary

Config activation checks Core itself and its Config binding, not Core's entire downstream graph. Construct drift after valid Core activation, leaving Core active/enabled. Config never calls Inventory interface/OHM/facility/lifecycle views.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-ENABLE-D23 | ADMIN_ROLE holder | Independently fuzz false/true; seed both | Independently fuzz false/true; seed all four pairs | Success when direct Core/local/history requirements pass | Exact local transition/events; no Inventory reads/writes; Core/loan/accounting state preserved | Covered: [test][test_givenIndependentInventoryState_whenActivated] |

[test_givenAdmin_whenEnabled]: ./enable.t.sol#L26
[test_whenCallerIsNotAdmin_reverts]: ./enable.t.sol#L41
[test_whenEnablePayloadIsNonempty_reverts]: ./enable.t.sol#L54
[test_givenAlreadyEnabled_whenActivationRetried_reverts]: ./enable.t.sol#L66
[test_givenInactivePolicy_whenActivated_reverts]: ./enable.t.sol#L79
[test_givenCoreInactiveEnabled_whenActivated_reverts]: ./enable.t.sol#L89
[test_givenCoreActiveDisabled_whenActivated_reverts]: ./enable.t.sol#L102
[test_givenCoreInactiveDisabled_whenActivated_reverts]: ./enable.t.sol#L115
[test_givenRevertingEnabled_whenActivated_reverts]: ./enable.t.sol#L129
[test_givenMalformedEnabled_whenActivated_reverts]: ./enable.t.sol#L146
[test_givenWrongKernel_whenActivated_reverts]: ./enable.t.sol#L159
[test_givenMissingCoreInterface_whenActivated_reverts]: ./enable.t.sol#L178
[test_givenMissingEnabler_whenActivated_reverts]: ./enable.t.sol#L198
[test_givenDifferentOhm_whenActivated_reverts]: ./enable.t.sol#L215
[test_givenDifferentConfigurator_whenActivated_reverts]: ./enable.t.sol#L228
[test_givenIndependentInventoryState_whenActivated]: ./enable.t.sol#L245
[test_givenFreshPolicyWithoutRoles_whenEnabled_reverts]: ./enable.t.sol#L263
[test_whenNonemptyPayloadBoundariesSeeded_reverts]: ./enable.t.sol#L272
[test_givenEnabled_whenNonemptyEnablePayloadSubmitted_reverts]: ./enable.t.sol#L296

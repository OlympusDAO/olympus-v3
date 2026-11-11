# BurnerLoansYieldClaimerTask.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

Required Core compatibility error: `BurnerLoansYieldClaimer_InvalidCore(Core)`. The implementation and focused tests use this selector for incompatible Core metadata.

## Dependency validation contract

Core is a required same-Kernel active/enabled service; do not require Core.core(). Validate interfaces/reported Kernel and the claimer settlement role. Payout is an operation-specific yield-routing service; use Core’s current selection rather than a separately cached copy. Core does not require this task enabled.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansYieldClaimer_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-A01 | Fuzz ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test][test_givenDisabled_whenAdminEnables] |
| BLYC-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test][test_givenUnauthorizedCaller_whenEnabled_reverts] |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Covered: [test][test_givenDisabled_whenPayloadIsNonempty_reverts], [test][test_whenPayloadBoundarySeeds_reverts] |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test][test_givenEnabled_whenEnabledAgain_reverts] |
| BLYC-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test][test_givenUnauthorizedCaller_whenEnabled_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | NotDisabled() | Unchanged; local transition state rejects before caller, payload and hooks | Covered: [test][test_givenEnabled_whenEnabledAgain_reverts] |

## Dependency lifecycle

Local enabled=false; data=0x; ROLES initialized. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Change only the condition named in each row. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-D01 | ADMIN_ROLE holder | Core | false | true | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenUnavailableCore_whenEnabled_reverts] |
| BLYC-ENABLE-D02 | ADMIN_ROLE holder | Core | true | false | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenUnavailableCore_whenEnabled_reverts] |
| BLYC-ENABLE-D03 | ADMIN_ROLE holder | Core | false | false | PolicyDependency_NotActive(Core) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenUnavailableCore_whenEnabled_reverts] |

## Settlement role prerequisite

Local enabled=false; data=0x; ROLES initialized. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Change only the condition named in each row. Core is active; all binding checks pass.

| ID | Caller | BL_YIELD_CLAIMER_ROLE held by local policy | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-P01 | ADMIN_ROLE holder | false | `ROLES_RequireRole(BL_YIELD_CLAIMER_ROLE)` | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenSettlementRoleRevoked_whenEnabled_reverts] |

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-D04 | ADMIN_ROLE holder | Core Kernel differs | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Covered: [test][test_givenCoreMigrated_whenEnabled_reverts] |

## Local activity

Local enabled=false; data=0x; ROLES initialized. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Change only the condition named in each row. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactiveTask_whenEnabled_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverActivated_whenEnabled_reverts] |

[test_givenCoreMigrated_whenEnabled_reverts]: enable.t.sol#L125
[test_givenDisabled_whenAdminEnables]: enable.t.sol#L26
[test_givenDisabled_whenPayloadIsNonempty_reverts]: enable.t.sol#L64
[test_givenEnabled_whenEnabledAgain_reverts]: enable.t.sol#L51
[test_givenInactiveTask_whenEnabled_reverts]: enable.t.sol#L144
[test_givenNeverActivated_whenEnabled_reverts]: enable.t.sol#L157
[test_givenSettlementRoleRevoked_whenEnabled_reverts]: enable.t.sol#L112
[test_givenUnauthorizedCaller_whenEnabled_reverts]: enable.t.sol#L38
[test_givenUnavailableCore_whenEnabled_reverts]: enable.t.sol#L88
[test_whenPayloadBoundarySeeds_reverts]: enable.t.sol#L74

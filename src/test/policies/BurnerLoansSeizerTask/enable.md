# BurnerLoansSeizerTask.enable coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [enable](../../../bases/EnablerV2.sol#L52). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-ENABLE` identifies this contract/function.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Implemented lifecycle payload rule: this contract does not use lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The concrete hook rejects nonempty data. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Constructor-bound Seize is the required operational Policy. Derive Core from Seize and require Lens.core() to match. Core readiness is enforced by Seize during settlement, without a separate Task activation gate. Lens is a plain constructor-bound helper: verify its interface/Core identity without inventing Kernel membership or enablement. Required settlement/task roles remain separate authorization prerequisites.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Readable Kernel mismatches use PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel); a zero or incompatible Seize target uses BurnerLoansSeizer_InvalidSeize(Seize); Lens mismatch uses BurnerLoansSeizer_InvalidLens; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility errors: readable Seize Kernel mismatch → `PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel)`; zero or incompatible Seize → `BurnerLoansSeizer_InvalidSeize(Seize)`; Lens/Core mismatch → `BurnerLoansSeizer_InvalidLens(Lens)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Unmapped |
| BLSEIZ-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Unmapped |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Unmapped; new hook enforces this restriction |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Unmapped |
| BLSEIZ-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Unmapped |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | NotDisabled() | Unchanged; local transition state rejects before caller, payload and hooks | Unmapped |

## Dependency lifecycle

For policy-service dependencies, active means membership in this consumer’s Kernel via `kernel.isPolicyActive(dependency)`, separately from a matching reported kernel(). Inactive-dependency cases retain a matching reported Kernel to prove that self-reporting alone cannot pass. A bound action or helper must report the consumer’s expected Core through core(); shared services such as DepositManager have no invented Core binding. Constructor identity binding may precede activation.

Local enabled=false; data=0x; ROLES initialized. Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Seize owns Core interface/Kernel validation. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. Change only the condition named in each row. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-D02 | ADMIN_ROLE holder | Seize | false | true | PolicyDependency_NotActive(Seize) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenSeizeInactiveOrDisabled_whenEnabled_reverts] |
| BLSEIZ-ENABLE-D05 | ADMIN_ROLE holder | Seize | false | false | PolicyDependency_NotActive(Seize) | Exact local transition/events on success; revert leaves state unchanged and commits no logs | Covered: [test][test_givenSeizeInactiveOrDisabled_whenEnabled_reverts] |
| BLSEIZ-ENABLE-D06 | ADMIN_ROLE holder | Seize | true | false | PolicyDependency_NotActive(Seize) | Unchanged; no logs | Covered: [test][test_givenSeizeInactiveOrDisabled_whenEnabled_reverts] |

Retired IDs: BLSEIZ-ENABLE-D01, BLSEIZ-ENABLE-D03, BLSEIZ-ENABLE-D04. Core is an identity reached through Seize/Lens, so its lifecycle is not part of the Task activation matrix. Only Seize readiness and Kernel identity are validated here; Lens must share Seize's Core identity.

Retired ID: BLSEIZ-ENABLE-D07. Core interface and Kernel checks belong to Seize, not Task.

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-D08 | ADMIN_ROLE holder | Seize Kernel differs | PolicyDependency_KernelMismatch(Seize,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Covered: [test][test_givenKernelDrift_whenEnabled_reverts] |
| BLSEIZ-ENABLE-D09 | ADMIN_ROLE holder | Lens reports a Core different from Seize.core() | BurnerLoansSeizer_InvalidLens(Lens) | Unchanged; no committed transition/logs | Covered: [test][test_givenLensCoreDrift_whenEnabled_reverts] |

## Local activity

Local enabled=false; data=0x; ROLES initialized. Seize must be active/enabled. Seize must report this Kernel, and Lens must report the same Core as Seize. Seize owns Core interface/Kernel validation. Core has no independent Task lifecycle gate. SeizerTask must be Kernel-active. Change only the condition named in each row. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-L02 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no activation, timestamp change or committed logs | Unmapped |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-ENABLE-L03 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Unmapped; fresh deployment, no dependency configuration |

## Test organization

[enable.t.sol](./enable.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

[test_givenKernelDrift_whenEnabled_reverts]: ./enable.t.sol#L19
[test_givenLensCoreDrift_whenEnabled_reverts]: ./enable.t.sol#L43
[test_givenSeizeInactiveOrDisabled_whenEnabled_reverts]: ./enable.t.sol#L65

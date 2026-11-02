# BurnerLoansDebt.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52). Implemented and mapped to the focused Foundry suite.

## Domains and notation

Normalized scenario scope: `BLDEBT-ENABLE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Required policy lifecycle: enable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Current missing checks are implementation gaps. Disable remains permitted while Kernel-inactive.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansDebt)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)` (implemented in the shared action base). Ordinary action entry checks local activity before local enablement/Core availability. Lifecycle transitions instead check local transition state and authorization before activation hooks, as shown below.

The shared action base rejects unused nonempty lifecycle data. Accept only `data.length == 0`; reject every nonempty payload with `BurnerLoans_InvalidEnablerData()`. Check local transition state and caller authorization first, then any existing settlement guard, then payload length, then enable-hook dependencies. The shared action base enforces this payload restriction. Authorization, lifecycle and dependency rows use `data=0x` unless a payload/competing-fault row explicitly overrides it. Existing nonempty-success tests are regression evidence to revise, not proof of this requirement.

Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)`. Missing required interfaces use `BurnerLoansAction_InvalidCore(Core)`.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Hook cases below isolate each activation dependency. Successful activation is covered in Authorization.

ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles.

## Dependency validation contract

Core and selected Inventory are required at activation. Validate Inventory against this action’s immutable Core, not an identity reported only by the candidate. Risk and fee-bearing Payout checks belong to the paths that consume them; Core being enabled is not proof that those services remain ready. Do not make zero-fee or Risk-free repayment paths depend on optional payout/pricing work.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansAction_InvalidCore(Core)`; Inventory → `BurnerLoansCore_InvalidInventory(Inventory)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-A01 | ADMIN_ROLE holder | data empty; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `Success` | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,data,now) | Covered: [test_givenDisabled_whenAdminEnables_thenExactTransition](enable.t.sol#L58) |
| BLDEBT-ENABLE-A02 | Fuzz caller excluding every ADMIN_ROLE holder | data empty; hook dependencies ready | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; no hook executed | Covered: [test_givenDisabled_whenUnauthorizedEnables_reverts](enable.t.sol#L48) |

## Local transition state

These checks run before authorization and hook dependencies. Fuzz all callers; make downstream dependency reads revert if reached. No requirement on their readiness is implied.

| ID | Caller | Local active | Local enabled | Prior transition L | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | `NotDisabled()` | Unchanged; no dependency reads or committed logs | Covered: [test_givenEnabled_whenAnyCallerEnables_reverts](enable.t.sol#L26) |

## Lifecycle

Inventory selected by Core is a direct operational dependency: it funds borrowing and reconciles repayment. Require it to be Kernel-active and locally enabled when enabling or re-enabling this action. The shared action base currently checks Core only; these Inventory activation checks remain required implementation work. Disabling the action still ignores Inventory readiness. Extension does not call Inventory; merging it into Debt does not add an Inventory gate to extend itself.

Local action disabled; reported Core Kernel matches; ROLES initialized; data=0x; ADMIN_ROLE holder runs every hook case. The same Core and Inventory admission requirements apply to enable and reEnable.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Action settlement role | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-L02 | ADMIN_ROLE holder | false | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansDebt) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenInactive_whenEnabled_reverts](enable.t.sol#L35) |
| BLDEBT-ENABLE-D01 | ADMIN_ROLE holder | true | false | true | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L105) |
| BLDEBT-ENABLE-D02 | ADMIN_ROLE holder | true | false | false | true | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreInactive_whenEnabled_thenRejectAndRetry](enable.t.sol#L133) |
| BLDEBT-ENABLE-D03 | ADMIN_ROLE holder | true | false | false | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreInactiveAndDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L118) |
| BLDEBT-ENABLE-L03 | ADMIN_ROLE holder | true | false | true | true | false | `ROLES_RequireRole(BL_DEBT_POLICY_ROLE)` | Unchanged; no committed logs | Covered: [test_givenSettlementRoleRevoked_whenEnabled_reverts](enable.t.sol#L230) |

## Inventory lifecycle

Local active=true, Local enabled=false, Core active=true and Core enabled=true; correct settlement role, reported Kernels and Inventory facility binding. Vary only the selected Inventory state after Core was successfully enabled, so Core stays enabled when Inventory is disabled or deactivated. Use empty data and initialized ROLES.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-D05 | ADMIN_ROLE holder | false | true | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryInactive_whenEnabled_thenRejectAndRetry](enable.t.sol#L197) |
| BLDEBT-ENABLE-D06 | ADMIN_ROLE holder | true | false | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L167) |
| BLDEBT-ENABLE-D07 | ADMIN_ROLE holder | false | false | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryInactiveAndDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L181) |
| BLDEBT-ENABLE-D08 | ADMIN_ROLE holder | true | true | Success after restoring the failed Inventory state and retrying | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); positions and balances preserved | Covered: [test_givenInventoryDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L167), [test_givenInventoryInactiveAndDisabled_whenEnabled_thenRejectAndRetry](enable.t.sol#L181), [test_givenInventoryInactive_whenEnabled_thenRejectAndRetry](enable.t.sol#L197) |

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed transition/logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-D04 | ADMIN_ROLE holder | Core reports another Kernel | `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)` | Covered: [test_givenCoreReportedKernelChanges_whenEnabled_thenKernelMismatch](enable.t.sol#L146) |

## Inputs

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed lifecycle or token events.

| ID | Caller | Payload | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-I01 | ADMIN_ROLE holder | data nonempty; fuzz length 1..256; seed 0x00, 0x01, ABI-encoded zero and 256 bytes; ROLES initialized; every dependency not varied by the selected table satisfies its concrete hook checks. | `BurnerLoans_InvalidEnablerData()` | Covered: [test_whenNonemptyEnableData_reverts](enable.t.sol#L75), [test_whenZeroBytePayload_reverts](enable.t.sol#L255), [test_whenNonzeroBytePayload_reverts](enable.t.sol#L260), [test_whenEncodedZeroPayload_reverts](enable.t.sol#L265), [test_whenMaximumPayloadPayload_reverts](enable.t.sol#L270) |

## Payload rejection and error precedence

Local enabled=false; initialized ROLES; dependencies compatible; outside settlement except explicit competing-fault rows. The empty payload is already covered by successful transitions. Fuzz nonempty lengths 1..256 with the listed deterministic seeds; the rule rejects every nonzero length, not only this test fixture range.

| ID | Caller | Payload / competing fault | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-I02 | Fuzz all callers | Nonempty bytes; local enabled=true | `NotDisabled()` | Unchanged; local state rejects before caller/data | Covered: [test_givenEnabled_whenNonemptyEnableData_thenStateWins](enable.t.sol#L85) |
| BLDEBT-ENABLE-I03 | Fuzz callers excluding every ADMIN_ROLE holder | Nonempty bytes; local enabled=false | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization rejects before data | Covered: [test_givenDisabled_whenUnauthorizedNonemptyEnable_thenAuthWins](enable.t.sol#L93) |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. data=0x. Match exact empty revert bytes for enable: an unset ROLES pointer cannot provide a boolean role result, so there is no custom-error selector to match. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLDEBT-ENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | Empty revert data from the unset ROLES dependency call; no decoded role result | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverActivated_whenEnabled_thenInitializationPrecedence](enable.t.sol#L242) |

# BurnerLoansConfig.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Normalized scenario scope: `BLCFG-REENABLE` identifies this contract/function. State and caller variations belong in table columns; case numbers identify distinct rows.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive. Core is the direct operational activation dependency and must be active and enabled; Inventory lifecycle does not gate Config activation.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Core is Config’s direct activation dependency: required interfaces, expected OHM/Kernel and active/enabled membership. Its selected Config authority must still match this contract. Inventory is not a direct dependency. Risk-specific calls validate the selected Risk when used; ordinary FLOAN-only parameter writes keep their approved independence from Core enablement.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansConfig_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test][test_givenWithinGrace_whenCallerHasNoRecoveryRole_reverts] |
| BLCFG-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test][test_whenCallerHasNoRecoveryRole_reverts] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test][test_givenGraceDeadlineOverflow_whenRecoveryRequested_reverts], [test][test_givenMaximumGraceAndTransitionTimestamp_whenRecoveryRequested] |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Dependency lifecycle-view failures

Local active=true; local enabled=false; compatible active dependencies and interfaces. Other dependency views succeed. For reEnable, use initialized history and valid grace. A false isEnabled result is already covered in Dependency lifecycle; the cases below test a failed or undecodable call.

| ID | Caller | Dependency | Lifecycle-view behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Mock isEnabled reverts with MockPolicyEnablerV2.MockBeforeEnableReverted() | PolicyDependency_InvalidDependency(Core) | Unchanged; no committed logs | Covered: [test][test_givenRevertingEnabled_whenActivated_reverts] |
| BLCFG-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Mock isEnabled returns 0x01, not an ABI-encoded bool | PolicyDependency_InvalidDependency(Core) | Unchanged; no committed logs | Covered: [test][test_givenMalformedEnabled_whenActivated_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Local transition state

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | NotDisabled() | Unchanged; before authorization and hook reads | Covered: [test][test_givenAlreadyEnabled_whenActivationRetried_reverts], [test][test_givenEnabledAtZeroTimestamp_whenRecoveryRequested_reverts] |
| BLCFG-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | NeverEnabled() | Unchanged; before authorization and hook reads | Covered: [test][test_givenNeverEnabled_whenRecoveryRequested_reverts], [test][test_givenActivatedButNeverEnabled_whenRecoveryRequested_reverts] |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Covered: [test][test_givenWithinGrace_whenRecoveryRequested], [test][test_givenGraceStartAndLastInteriorSecond_whenRecoveryRequested] |
| BLCFG-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Covered: [test][test_givenExactDeadline_whenRecoveryRequested], [test][test_givenMaximumRepresentableDeadline_whenRecoveryAtDeadline] |
| BLCFG-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Covered: [test][test_givenExpiredGrace_whenRecoveryRequested_reverts], [test][test_givenExpiredGraceBoundarySeeds_whenRecoveryRequested_reverts] |

## Dependency lifecycle

For policy-service dependencies, active means membership in this consumer’s Kernel via `kernel.isPolicyActive(dependency)`, separately from a matching reported kernel(). Inactive-dependency cases retain a matching reported Kernel to prove that self-reporting alone cannot pass. A bound action or helper must report the consumer’s expected Core through core(); shared services such as DepositManager have no invented Core binding. Constructor identity binding may precede activation.

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Fuzz both permitted role classes through every enable prerequisite. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-D05 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | false | true | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenCoreInactiveEnabled_whenActivated_reverts] |
| BLCFG-REENABLE-D07 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | true | false | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenCoreActiveDisabled_whenActivated_reverts] |
| BLCFG-REENABLE-D09 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | false | false | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenCoreInactiveDisabled_whenActivated_reverts] |

## Dependency compatibility

A canonical Core kernel() read reporting another Kernel uses PolicyDependency_KernelMismatch(Core,ConfigKernel,reportedKernel), with ConfigKernel equal to this Config’s Kernel. Failed/malformed Kernel/status reads use PolicyDependency_InvalidDependency(Core); other incompatible Core identity/selection faults retain BurnerLoansConfig_InvalidCore(Core). Apply this error distinction identically in enable and reEnable.

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Fuzz both permitted role classes through every enable prerequisite. Dependency lifecycle otherwise satisfies the listed defaults.

| ID | Caller | Component | Binding / interface fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-D11 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core reports another Kernel | `PolicyDependency_KernelMismatch(Core,ConfigKernel,reportedKernel)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenWrongKernel_whenActivated_reverts] |
| BLCFG-REENABLE-D12 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core lacks IBurnerLoansCore | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenMissingCoreInterface_whenActivated_reverts] |
| BLCFG-REENABLE-D13 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core lacks IEnabler | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenMissingEnabler_whenActivated_reverts] |
| BLCFG-REENABLE-D14 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core reports different OHM | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenDifferentOhm_whenActivated_reverts] |
| BLCFG-REENABLE-D15 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core | Core selects another Config | `BurnerLoansConfig_InvalidCore(Core)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenDifferentConfigurator_whenActivated_reverts] |

## Local activity

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is not a direct Config dependency and has independent configuration authority. Core must be active/enabled; Config must be Kernel-active. These checks are required where missing in the current implementation. Fuzz both permitted role classes through every enable prerequisite. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactivePolicy_whenActivated_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverEnabled_whenRecoveryRequested_reverts] |

## Direct dependency boundary

Config activation checks Core itself and its Config binding, not Core's entire downstream graph. Construct drift after valid Core activation, leaving Core active/enabled. Config never calls Inventory interface/OHM/facility/lifecycle views.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCFG-REENABLE-D23 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz false/true; seed both | Independently fuzz false/true; seed all four pairs | Success when direct Core/local/history requirements pass | Exact local transition/events; no Inventory reads/writes; Core/loan/accounting state preserved | Covered: [test][test_givenIndependentInventoryState_whenActivated] |

[test_whenCallerHasNoRecoveryRole_reverts]: ./reEnable.t.sol#L39
[test_givenAlreadyEnabled_whenActivationRetried_reverts]: ./reEnable.t.sol#L54
[test_givenInactivePolicy_whenActivated_reverts]: ./reEnable.t.sol#L67
[test_givenCoreInactiveEnabled_whenActivated_reverts]: ./reEnable.t.sol#L82
[test_givenCoreActiveDisabled_whenActivated_reverts]: ./reEnable.t.sol#L100
[test_givenCoreInactiveDisabled_whenActivated_reverts]: ./reEnable.t.sol#L118
[test_givenRevertingEnabled_whenActivated_reverts]: ./reEnable.t.sol#L137
[test_givenMalformedEnabled_whenActivated_reverts]: ./reEnable.t.sol#L159
[test_givenWrongKernel_whenActivated_reverts]: ./reEnable.t.sol#L177
[test_givenMissingCoreInterface_whenActivated_reverts]: ./reEnable.t.sol#L201
[test_givenMissingEnabler_whenActivated_reverts]: ./reEnable.t.sol#L226
[test_givenDifferentOhm_whenActivated_reverts]: ./reEnable.t.sol#L248
[test_givenDifferentConfigurator_whenActivated_reverts]: ./reEnable.t.sol#L266
[test_givenIndependentInventoryState_whenActivated]: ./reEnable.t.sol#L288
[test_givenNeverEnabled_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L311
[test_givenWithinGrace_whenRecoveryRequested]: ./reEnable.t.sol#L319
[test_givenExactDeadline_whenRecoveryRequested]: ./reEnable.t.sol#L347
[test_givenExpiredGrace_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L374
[test_givenGraceDeadlineOverflow_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L399
[test_givenWithinGrace_whenCallerHasNoRecoveryRole_reverts]: ./reEnable.t.sol#L424
[test_givenEnabledAtZeroTimestamp_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L439
[test_givenActivatedButNeverEnabled_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L454
[test_givenMaximumRepresentableDeadline_whenRecoveryAtDeadline]: ./reEnable.t.sol#L467
[test_givenExpiredGraceBoundarySeeds_whenRecoveryRequested_reverts]: ./reEnable.t.sol#L478
[test_givenMaximumGraceAndTransitionTimestamp_whenRecoveryRequested]: ./reEnable.t.sol#L497
[test_givenGraceStartAndLastInteriorSecond_whenRecoveryRequested]: ./reEnable.t.sol#L513

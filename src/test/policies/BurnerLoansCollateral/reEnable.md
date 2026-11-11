# BurnerLoansCollateral.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Test mappings describe the verified scope of each named test.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope: `BLCOL-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Current missing checks are implementation gaps. Disable remains permitted while Kernel-inactive.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)` (implemented in the shared action base). Ordinary action entry checks local activity before local enablement/Core availability. Lifecycle transitions instead check local transition state and authorization before activation hooks, as shown below.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Readable foreign-Kernel metadata uses `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)`. Missing required interfaces use `BurnerLoansAction_InvalidCore(Core)`.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

Hook cases below isolate each activation dependency. Successful re-enablement is covered across the valid time interval.

All concrete hook dependencies listed below satisfied; ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

Core is the activation dependency; it must expose the Core/lifecycle/version interfaces and be active/enabled in the action’s Kernel. Core itself is not a Core-bound component, so do not require Core.core(). Risk is used by debt-bearing action paths, not by debt-free deposits/withdrawals. Do not recursively gate all actions on every service selected by Core.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansAction_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test_givenDisabled_whenUnauthorizedCaller_reverts][test_givenDisabled_whenUnauthorizedCaller_reverts] |
| BLCOL-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins][test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins] |

## Local transition state

These checks run before authorization and hook dependencies. Fuzz all callers; make downstream dependency reads revert if reached. No requirement on their readiness is implied.

| ID | Caller | Local active | Local enabled | Prior transition L | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | `NotDisabled()` | Unchanged; before caller, grace and dependencies | Covered: [test_givenEnabled_whenAnyCaller_reverts][test_givenEnabled_whenAnyCaller_reverts] |
| BLCOL-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | `NeverEnabled()` | Unchanged; before caller, grace and dependencies | Covered: [test_givenNeverEnabled_whenAnyCaller_reverts][test_givenNeverEnabled_whenAnyCaller_reverts] |

## Lifecycle

Local action disabled; reported Core Kernel matches; ROLES initialized; previous transition L>0 and independently fuzz now within the valid grace interval. Independently fuzz the permitted caller role in every hook case, with both exclusive-role seeds guaranteed. The same admission dependencies are checked by enable and reEnable.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Action settlement role | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenDisabled_givenPolicyInactive_reverts][test_givenDisabled_givenPolicyInactive_reverts] |
| BLCOL-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | true | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry][test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry] |
| BLCOL-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | false | true | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry][test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry] |
| BLCOL-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | false | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry][test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry] |
| BLCOL-REENABLE-L04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | true | true | false | `ROLES_RequireRole(BL_COLLATERAL_POLICY_ROLE)` | Unchanged; no committed logs | Covered: [test_givenDisabled_givenSettlementRoleRevoked_reverts][test_givenDisabled_givenSettlementRoleRevoked_reverts] |

## Timing and transition history

Action locally disabled and Kernel-active; same-Kernel Core active+enabled; settlement role held; every other dependency compatible. L>0, G=gracePeriod>0, D=L+G<=MAX48. Fuzz L,G independently within that relationship. Each row preserves grants, debt, collateral, funding and payouts.

| ID | Caller | Now / fuzz interval / seeds | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz now in L..D-1; seed L,D-1; seed L=MAX48-G to reach maximum representable D | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now) | Covered: [test_givenDisabled_givenValidGrace_whenPermittedCaller][test_givenDisabled_givenValidGrace_whenPermittedCaller], [test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled][test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled] |
| BLCOL-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | now=D; fuzz compatible L,G; seed D=MAX48 | Success | Same exact transition; inclusive deadline | Covered: [test_givenDisabled_givenExactDeadline_whenAdminOnly][test_givenDisabled_givenExactDeadline_whenAdminOnly], [test_givenDisabled_whenExactFuzzedDeadline_thenAllPermittedCallers][test_givenDisabled_whenExactFuzzedDeadline_thenAllPermittedCallers], [test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled][test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled] |
| BLCOL-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | `GracePeriod_Expired(D)` | Unchanged; no committed logs | Covered: [test_givenDisabled_givenGraceExpired_reverts][test_givenDisabled_givenGraceExpired_reverts], [test_givenEveryPermittedRole_whenExpiredEndpoints_thenExactDeadlineError][test_givenEveryPermittedRole_whenExpiredEndpoints_thenExactDeadlineError] |

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed transition/logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOL-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core reports another Kernel; lastTransitionAt nonzero; within grace | `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)` | Covered: [test_givenDisabled_givenCoreKernelChanged_reverts][test_givenDisabled_givenCoreKernelChanged_reverts] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test_givenDeadlineOverflow_reverts][test_givenDeadlineOverflow_reverts], [test_givenEveryPermittedRole_whenDeadlineOverflowEndpoints_thenTypedError][test_givenEveryPermittedRole_whenDeadlineOverflowEndpoints_thenTypedError] |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. This action owns no custody or position state; recovery must preserve Core grants and all canonical positions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOL-REENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverActivated_whenCalled_thenInitializationPrecedence][test_givenNeverActivated_whenCalled_thenInitializationPrecedence] |

## Focused implementation status

Constructor and lifecycle suites pass with solc 0.8.36, optimizer 400 and no via IR. This fixture uses real Kernel/ROLES and an existing enabled-policy mock for the Core identity. It does not prove real loan/custody preservation, settlement callbacks, or the full boundary/payload seed matrix. Deposit/withdrawal units and real-dependency integration remain pending.

[test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L80
[test_givenDeadlineOverflow_reverts]: reEnable.t.sol#L165
[test_givenDisabled_givenCoreKernelChanged_reverts]: reEnable.t.sol#L128
[test_givenDisabled_givenExactDeadline_whenAdminOnly]: reEnable.t.sol#L210
[test_givenDisabled_givenGraceExpired_reverts]: reEnable.t.sol#L106
[test_givenDisabled_givenPolicyInactive_reverts]: reEnable.t.sol#L63
[test_givenDisabled_givenSettlementRoleRevoked_reverts]: reEnable.t.sol#L150
[test_givenDisabled_givenValidGrace_whenPermittedCaller]: reEnable.t.sol#L190
[test_givenDisabled_whenExactFuzzedDeadline_thenAllPermittedCallers]: reEnable.t.sol#L240
[test_givenDisabled_whenUnauthorizedCaller_reverts]: reEnable.t.sol#L52
[test_givenEachCoreLifecycleFailure_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L352
[test_givenEnabled_whenAnyCaller_reverts]: reEnable.t.sol#L40
[test_givenEveryPermittedRole_whenDeadlineOverflowEndpoints_thenTypedError]: reEnable.t.sol#L309
[test_givenEveryPermittedRole_whenExpiredEndpoints_thenExactDeadlineError]: reEnable.t.sol#L286
[test_givenEveryPermittedRole_whenGraceBoundarySeedsUsed_thenEnabled]: reEnable.t.sol#L253
[test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins]: reEnable.t.sol#L338
[test_givenNeverActivated_whenCalled_thenInitializationPrecedence]: reEnable.t.sol#L325
[test_givenNeverEnabled_whenAnyCaller_reverts]: reEnable.t.sol#L31

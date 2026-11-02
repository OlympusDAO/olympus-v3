# BurnerLoansYieldClaimerTask.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

Implemented parity: enable/reEnable share the own-policy, Core operational/binding and BL_YIELD_CLAIMER_ROLE checks. Revoked-role reEnable rejects without transition.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

Required Core compatibility error: `BurnerLoansYieldClaimer_InvalidCore(Core)`. The implementation and focused tests use this selector for incompatible Core metadata.

## Dependency validation contract

Core is a required same-Kernel active/enabled service; do not require Core.core(). Validate interfaces/reported Kernel and the claimer settlement role. Payout is an operation-specific yield-routing service; use Core’s current selection rather than a separately cached copy. Core does not require this task enabled.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansYieldClaimer_InvalidCore(Core)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenReEnabled_reverts] |
| BLYC-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test][test_givenUnauthorizedCaller_whenReEnabled_reverts] |
| BLYC-REENABLE-A03 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Task Kernel-active and locally disabled; initialized lastTransitionAt; inclusive grace valid; Core/bindings/settlement role ready | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); accounting/configuration unchanged | Covered: [test][test_givenWithinGrace_whenPermittedCallerReEnables], [test][test_whenValidTimeAndRoleBoundarySeeds] |
| BLYC-REENABLE-A04 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Task Kernel-active and locally disabled; initialized lastTransitionAt; inclusive grace valid; Core/bindings/settlement role ready | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); accounting/configuration unchanged | Covered: [test][test_givenWithinGrace_whenPermittedCallerReEnables], [test][test_whenValidTimeAndRoleBoundarySeeds] |
| BLYC-REENABLE-A05 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Task Kernel-active and locally disabled; initialized lastTransitionAt; inclusive grace valid; Core/bindings/settlement role ready | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); accounting/configuration unchanged | Covered: [test][test_givenWithinGrace_whenPermittedCallerReEnables], [test][test_whenValidTimeAndRoleBoundarySeeds] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-N01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test][test_givenOverflowingDeadline_whenReEnabled_reverts], [test][test_whenOverflowBoundarySeeds_reverts] |

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
| BLYC-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | NotDisabled() | Unchanged; before authorization and hook reads | Covered: [test][test_givenEnabled_whenReEnabled_reverts], [test][test_givenEnabledAtTimestampZero_whenReEnabled_reverts] |
| BLYC-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | NeverEnabled() | Unchanged; before authorization and hook reads | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts] |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Covered: [test][test_givenWithinGrace_whenPermittedCallerReEnables], [test][test_whenValidTimeAndRoleBoundarySeeds] |
| BLYC-REENABLE-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Covered: [test][test_givenExactDeadline_whenReEnabled], [test][test_whenValidTimeAndRoleBoundarySeeds] |
| BLYC-REENABLE-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Covered: [test][test_givenExpiredGrace_whenReEnabled_reverts], [test][test_whenExpiredTimeBoundarySeeds_reverts] |

## Dependency lifecycle

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Fuzz both permitted role classes through every enable prerequisite. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-D01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Core | false | true | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenReEnabled_reverts] |
| BLYC-REENABLE-D02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Core | true | false | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenReEnabled_reverts] |
| BLYC-REENABLE-D03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Core | false | false | PolicyDependency_NotActive(Core) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenReEnabled_reverts] |

## Settlement role prerequisite

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Fuzz both permitted role classes through every enable prerequisite. Core is active; all binding checks pass.

| ID | Caller | BL_YIELD_CLAIMER_ROLE held by local policy | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-P04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | false | `ROLES_RequireRole(BL_YIELD_CLAIMER_ROLE)` | Exact local transition/events on Success; otherwise Unchanged | Covered: [test][test_givenSettlementRoleRevoked_whenReEnabled_reverts] |

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-D04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Core Kernel differs | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Covered: [test][test_givenCoreMigrated_whenReEnabled_reverts] |

## Local activity

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. Core must be active/enabled and report this Kernel. Claimer must be Kernel-active and hold BL_YIELD_CLAIMER_ROLE at enable and reEnable. Fuzz both permitted role classes through every enable prerequisite. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-L03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | false | false | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no activation, timestamp change or committed logs | Covered: [test][test_givenInactiveTask_whenReEnabled_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test][test_givenNeverEnabled_whenReEnabled_reverts] |

[test_givenCoreMigrated_whenReEnabled_reverts]: reEnable.t.sol#L226
[test_givenEnabledAtTimestampZero_whenReEnabled_reverts]: reEnable.t.sol#L304
[test_givenEnabled_whenReEnabled_reverts]: reEnable.t.sol#L116
[test_givenExactDeadline_whenReEnabled]: reEnable.t.sol#L56
[test_givenExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L141
[test_givenInactiveTask_whenReEnabled_reverts]: reEnable.t.sol#L248
[test_givenNeverEnabled_whenReEnabled_reverts]: reEnable.t.sol#L124
[test_givenOverflowingDeadline_whenReEnabled_reverts]: reEnable.t.sol#L165
[test_givenSettlementRoleRevoked_whenReEnabled_reverts]: reEnable.t.sol#L210
[test_givenUnauthorizedCaller_whenReEnabled_reverts]: reEnable.t.sol#L99
[test_givenUnavailableCore_whenReEnabled_reverts]: reEnable.t.sol#L188
[test_givenWithinGrace_whenPermittedCallerReEnables]: reEnable.t.sol#L35
[test_whenExpiredTimeBoundarySeeds_reverts]: reEnable.t.sol#L266
[test_whenOverflowBoundarySeeds_reverts]: reEnable.t.sol#L283
[test_whenValidTimeAndRoleBoundarySeeds]: reEnable.t.sol#L75

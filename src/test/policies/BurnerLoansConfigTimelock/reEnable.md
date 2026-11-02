# BurnerLoansConfigTimelock.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage is recorded in the Test column.

Implementation: 15 scenario functions mapped; 12 Covered, 3 Partial. Partial rows have complete test implementations blocked by the current production behavior.

## Domains and notation

Scenario scope: `BLCT-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Disable remains permitted while Kernel-inactive.

For grace fuzzing, `L=lastTransitionAt>0`, `G=gracePeriod>0`, `D=L+G`. Use compatible setup with `L<=MAX48-G`; fuzz valid now in L..D and expired now in D+1..MAX48 only when D<MAX48. Seed L,D-1,D,D+1,MAX48 where each belongs to the selected outcome. Vary time independently from the configured deadline; no single-boundary test substitutes for interval coverage.

`reEnable()` is parameterless. Successful Transition always carries empty data; there is no bytes argument to validate.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Initialization history matters independently of Kernel membership. Previously Kernel-activated, then deactivated policies retain their cached ROLES address; ROLES.hasRole is a public getter, so deactivation does not by itself prevent caller authorization. In every inactive-success or inactive-hook case below, Kernel activation/configureDependencies has already initialized ROLES. A fresh never-activated policy with configureDependencies never called has ROLES=address(0), local enabled=false and lastTransitionAt=0. It is not equivalent to a deactivated, previously enabled policy. Do not fabricate local enabled=true with ROLES=0 by storage mutation as an ordinary lifecycle fixture.

Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each: independently fuzz a nonzero caller and grant ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE. Guarantee seeds with ADMIN_ROLE only, BURNER_LOANS_ADMIN_ROLE only and both roles; select the role independently from time and dependency inputs. These roles follow the same reEnable behavior, so each equivalent validation/time case has one row. Fuzz permitted callback caller uses a callback contract holding the selected role, with the outer operation initiated by its separately authorized caller.

The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. ROLES initialized. The permitted caller fuzz family above names every accepted role; unauthorized fuzzing excludes all holders of those roles. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Dependency validation contract

The immutable Config target is a required same-Kernel active/enabled Policy that selects this timelock as its configOperator. Config owns its relationship with Core; the timelock does not revalidate Core’s Config selection. Target authority matching is separate from readiness. Risk is checked only for Risk-targeted proposals; no global Risk-operator equality or recursive Core/Inventory readiness gate is introduced.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: invalid Config metadata → `BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(Config)`; a readable Config Kernel different from this timelock’s Kernel → `PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel)`. This distinct Kernel-mismatch rule applies to both enable and reEnable. Missing validation/error-name changes remain implementation work.

## Authorization

Fixed for this table: Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test_givenUnauthorizedWithinGrace_whenReEnabled_thenAuthorizationFirst][test_givenUnauthorizedWithinGrace_whenReEnabled_thenAuthorizationFirst] |
| BLCT-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test_givenUnauthorizedExpiredGraceWithUnavailableConfig_whenReEnabled_thenAuthorizationFirst][test_givenUnauthorizedExpiredGraceWithUnavailableConfig_whenReEnabled_thenAuthorizationFirst] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test_givenOverflowDeadline_whenReEnabled_reverts][test_givenOverflowDeadline_whenReEnabled_reverts]; [test_givenGraceN01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceN01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

Implemented lifecycle payload rule: calculate D=uint256(L)+uint256(G), then use checked SafeCast narrowing to uint48. If D exceeds MAX48, revert with SafeCastOverflowedUintDowncast(48,D). The product-local _requireGrace override uses widened addition and checked uint48 narrowing; it leaves shared ReEnabler behavior unchanged. Preserve local enabled state, transition timestamp, configuration and balances; commit no lifecycle events. The duration setter cannot validate an unknown future disable timestamp.

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Local transition state

| ID | Caller | Local active | Local enabled | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | NotDisabled() | Unchanged; before authorization and hook reads | Covered: [test_givenAlreadyEnabled_whenReEnabled_thenStateError][test_givenAlreadyEnabled_whenReEnabled_thenStateError] |
| BLCT-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | NeverEnabled() | Unchanged; before authorization and hook reads | Covered: [test_givenNeverEnabledActivated_whenReEnabled_thenNeverEnabledFirst][test_givenNeverEnabledActivated_whenReEnabled_thenNeverEnabledFirst] |

## Timing and transition history

Local enabled=false; L=lastTransitionAt>0; G=gracePeriod>0; D=L+G<=MAX48. The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. Core settlement guard is not entered. Seed boundaries through the same case assertions; no now/deadline correlation.

| ID | Caller | Time domain / boundary seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Independently fuzz L,G with 0<L<=MAX48-G; fuzz now in L..D-1; seed L,D-1 and D=MAX48 | Success | Enabled then Transition(caller,true,0x,now); lastTransitionAt=now | Covered: [test_givenBeforeDeadline_whenReEnabled_thenExactTransition][test_givenBeforeDeadline_whenReEnabled_thenExactTransition]; [test_givenGraceP01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceP01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G; now=D; seed D=MAX48 | Success | Inclusive deadline; exact local transition/events | Covered: [test_givenAtDeadline_whenReEnabled_thenExactTransition][test_givenAtDeadline_whenReEnabled_thenExactTransition]; [test_givenGraceP02RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceP02RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCT-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz compatible L,G with D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | GracePeriod_Expired(D) | Unchanged; no committed logs | Covered: [test_givenAfterDeadline_whenReEnabled_reverts][test_givenAfterDeadline_whenReEnabled_reverts]; [test_givenGraceP03RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceP03RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Dependency lifecycle

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. Fuzz both permitted role classes through every enable prerequisite. All dependencies except the one named in each row retain those explicit defaults. Local state/time and authorization are fixed above; activity and enablement are independent columns.

| ID | Caller | Dependency | Dependency active | Dependency enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Config | false | true | PolicyDependency_NotActive(Config) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenConfigActiveFalse_givenConfigEnabledTrue_whenReenable_reverts][test_givenConfigActiveFalse_givenConfigEnabledTrue_whenReenable_reverts] |
| BLCT-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Config | true | false | PolicyDependency_NotActive(Config) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenConfigActiveTrue_givenConfigEnabledFalse_whenReenable_reverts][test_givenConfigActiveTrue_givenConfigEnabledFalse_whenReenable_reverts] |
| BLCT-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Config | false | false | PolicyDependency_NotActive(Config) | Exact local transition/events on Success; otherwise Unchanged | Covered: [test_givenConfigActiveFalse_givenConfigEnabledFalse_whenReenable_reverts][test_givenConfigActiveFalse_givenConfigEnabledFalse_whenReenable_reverts] |

## Dependency compatibility

Local active=true; local enabled=false; initialized ROLES; all operational dependencies active/enabled; data=0x for enable, valid grace/history for reEnable. Vary one binding fault at a time. Validate these bindings directly; no additional registry or validator contract is needed.

| ID | Caller | Binding fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Config Kernel differs | PolicyDependency_KernelMismatch(Config,expectedKernel,reportedKernel) | Unchanged; no committed transition/logs | Covered: [test_givenForeignConfigKernel_whenReenable_reverts][test_givenForeignConfigKernel_whenReenable_reverts] |

Retired: `BLCT-REENABLE-D05`.

## Local activity

Local enabled=false; prior L>0; independently fuzz a representable valid grace interval. The immutable Config must be active/enabled and report this Kernel. This Timelock must be Kernel-active. Fuzz both permitted role classes through every enable prerequisite. Own policy activity is required; the concrete hook checks local activity.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenOwnPolicyInactive_whenReenable_reverts][test_givenOwnPolicyInactive_whenReenable_reverts] |

## Never-activated policy

Use the actual constructor and never call configureDependencies or Kernel ActivatePolicy. Other bound contracts remain valid. This table tests admission precedence without assuming that a requested role is readable through this policy.

| ID | Caller | Local active | Local enabled | Cached ROLES | lastTransitionAt | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-L04 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverEnabledUninitialized_whenReEnabled_thenNeverEnabledFirst][test_givenNeverEnabledUninitialized_whenReEnabled_thenNeverEnabledFirst] |

## Independent optional Risk authority

This timelock may serve market configuration, direct Risk cache-age configuration, or both. Keep the existing Config activation requirements; activation does not require Risk to delegate its configuration authority to BLCT. Risk-targeted queue/execution performs its own readiness, same-Kernel and selected-operator checks; market-only operation remains possible when Risk uses another controller.

| ID | Caller | Risk operator | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCT-REENABLE-D06 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only or both | Zero or controller distinct from Core Config and BLCT; guarantee both | Success with existing local/history/Config prerequisites satisfied | Normal local transition; Risk authority/cache/oracle/age untouched; no equality requirement | Covered: [test_givenRiskOperatorIndependent_whenReenable_thenEnabled][test_givenRiskOperatorIndependent_whenReenable_thenEnabled] |

[test_givenUnauthorizedWithinGrace_whenReEnabled_thenAuthorizationFirst]: reEnable.t.sol#L130
[test_givenUnauthorizedExpiredGraceWithUnavailableConfig_whenReEnabled_thenAuthorizationFirst]: reEnable.t.sol#L143
[test_givenOverflowDeadline_whenReEnabled_reverts]: reEnable.t.sol#L264
[test_givenGraceN01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: reEnable.t.sol#L373
[test_givenAlreadyEnabled_whenReEnabled_thenStateError]: reEnable.t.sol#L158
[test_givenNeverEnabledActivated_whenReEnabled_thenNeverEnabledFirst]: reEnable.t.sol#L171
[test_givenBeforeDeadline_whenReEnabled_thenExactTransition]: reEnable.t.sol#L196
[test_givenGraceP01RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: reEnable.t.sol#L289
[test_givenAtDeadline_whenReEnabled_thenExactTransition]: reEnable.t.sol#L219
[test_givenGraceP02RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: reEnable.t.sol#L320
[test_givenAfterDeadline_whenReEnabled_reverts]: reEnable.t.sol#L241
[test_givenGraceP03RoleAndTimeEndpoints_whenBoundarySeedsRun_thenScenarioHolds]: reEnable.t.sol#L342
[test_givenConfigActiveFalse_givenConfigEnabledTrue_whenReenable_reverts]: reEnable.t.sol#L22
[test_givenConfigActiveTrue_givenConfigEnabledFalse_whenReenable_reverts]: reEnable.t.sol#L40
[test_givenConfigActiveFalse_givenConfigEnabledFalse_whenReenable_reverts]: reEnable.t.sol#L58
[test_givenForeignConfigKernel_whenReenable_reverts]: reEnable.t.sol#L76
[test_givenOwnPolicyInactive_whenReenable_reverts]: reEnable.t.sol#L101
[test_givenNeverEnabledUninitialized_whenReEnabled_thenNeverEnabledFirst]: reEnable.t.sol#L184
[test_givenRiskOperatorIndependent_whenReenable_thenEnabled]: reEnable.t.sol#L115

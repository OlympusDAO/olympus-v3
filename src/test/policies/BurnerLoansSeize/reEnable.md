# BurnerLoansSeize.reEnable coverage plan

Source: [reEnable](../../../bases/ReEnabler.sol#L46). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope: `BLLIQ-REENABLE` identifies this contract/function.

Required policy lifecycle: reEnable requires the subject policy to be Kernel-active, with disabled local state and valid caller/history. Operational dependencies must be ready and correctly bound; identity references do not inherit operational enablement requirements. Current missing checks are implementation gaps. Disable remains permitted while Kernel-inactive.

Error ownership: an inactive local action uses `BurnerLoans_PolicyNotActive(BurnerLoansSeize)`; a locally disabled action uses inherited `NotEnabled()`. An inactive or disabled Core uses `PolicyDependency_NotActive(Core)` (implemented in the shared action base). Ordinary action entry checks local activity before local enablement/Core availability. Lifecycle transitions instead check local transition state and authorization before activation hooks, as shown below.

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

Core, selected Inventory and selected Payout are required at activation. Inventory/Payout must expose the shared Core binding and match this action’s immutable Core, in addition to their interface, Kernel and active/enabled checks. Live seizure also consumes the selected Risk; never infer current readiness solely from Core’s enabled flag.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: Core → `BurnerLoansAction_InvalidCore(Core)`; Inventory → `BurnerLoansCore_InvalidInventory(Inventory)`; Payout → `BurnerLoansCore_InvalidPayout(Payout)`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-A01 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; within grace | `NotAuthorised()` | Unchanged | Covered: [test_givenDisabled_whenUnauthorizedReEnables_reverts][test_givenDisabled_whenUnauthorizedReEnables_reverts] |
| BLLIQ-REENABLE-A02 | Fuzz caller excluding all ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE holders | lastTransitionAt nonzero; expired grace; one failed dependency | `NotAuthorised()` | Unchanged; authorization before grace/dependency | Covered: [test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins][test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins] |

## Local transition state

These checks run before authorization and hook dependencies. Fuzz all callers; make downstream dependency reads revert if reached. No requirement on their readiness is implied.

| ID | Caller | Local active | Local enabled | Prior transition L | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-L01 | Fuzz all callers | Fuzz false/true | true | Fuzz zero/nonzero | `NotDisabled()` | Unchanged; before caller, grace and dependencies | Covered: [test_givenEnabled_whenAnyCallerReEnables_reverts][test_givenEnabled_whenAnyCallerReEnables_reverts], [test_givenZeroTransitionHistory_whenAlreadyEnabled_thenStateWins][test_givenZeroTransitionHistory_whenAlreadyEnabled_thenStateWins] |
| BLLIQ-REENABLE-L02 | Fuzz all callers | Fuzz false/true | false | 0 | `NeverEnabled()` | Unchanged; before caller, grace and dependencies | Covered: [test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence][test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence], [test_givenActivatedButNeverEnabled_whenReEnabled_thenHistoryWins][test_givenActivatedButNeverEnabled_whenReEnabled_thenHistoryWins] |

## Lifecycle

Inventory selected by Core is a direct operational dependency: liquidation records principal defaults there. Require it to be Kernel-active and locally enabled when enabling or re-enabling this action. The concrete Seize activation hook checks Inventory and Payout in addition to Core. Disabling the action still ignores Inventory readiness.

Local action disabled; reported Core Kernel matches; ROLES initialized; previous transition L>0 and independently fuzz now within the valid grace interval. Independently fuzz the permitted caller role in every hook case, with both exclusive-role seeds guaranteed. The same Core and Inventory admission requirements apply to enable and reEnable.

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Action settlement role | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-L03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | true | true | true | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | Unchanged; no activation, timestamp change or committed logs | Covered: [test_givenInactive_whenReEnabled_reverts][test_givenInactive_whenReEnabled_reverts], [test_givenEachPermittedRole_givenInactive_whenReEnabled_reverts][test_givenEachPermittedRole_givenInactive_whenReEnabled_reverts] |
| BLLIQ-REENABLE-D01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | true | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | false | true | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | false | false | true | `PolicyDependency_NotActive(Core)` | Unchanged; no committed logs | Covered: [test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry][test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-L04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | true | true | false | `ROLES_RequireRole(BL_LIQUIDATION_POLICY_ROLE)` | Unchanged; no committed logs | Covered: [test_givenSettlementRoleRevoked_whenReEnabled_reverts][test_givenSettlementRoleRevoked_whenReEnabled_reverts], [test_givenEachPermittedRole_givenSettlementRoleRevoked_whenReEnabled_reverts][test_givenEachPermittedRole_givenSettlementRoleRevoked_whenReEnabled_reverts] |

## Inventory lifecycle

Local active=true, Local enabled=false, Core active=true and Core enabled=true; correct settlement role, reported Kernels and Inventory facility binding. Vary only the selected Inventory state after Core was successfully enabled, so Core stays enabled when Inventory is disabled or deactivated. Use initialized transition history and independently fuzz now in the valid grace interval.

| ID | Caller | Inventory active | Inventory enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-D05 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | true | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry][test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D06 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | false | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry][test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D07 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | false | false | `PolicyDependency_NotActive(Inventory)` | Unchanged; no local transition, timestamp update or committed logs | Covered: [test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry][test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D08 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | true | true | Success after restoring the failed Inventory state and retrying | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now); positions and balances preserved | Covered: [test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry][test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry] |

## Timing and transition history

Action locally disabled and Kernel-active; same-Kernel Core active+enabled; settlement role held; every other dependency compatible. L>0, G=gracePeriod>0, D=L+G<=MAX48. Fuzz L,G independently within that relationship. Each row preserves grants, debt, collateral, funding and payouts.

| ID | Caller | Now / fuzz interval / seeds | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-P01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz now in L..D-1; seed L,D-1; seed L=MAX48-G to reach maximum representable D | Success | isEnabled=true; lastTransitionAt=now; Enabled then Transition(caller,true,0x,now) | Covered: [test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition][test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition], [test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition][test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition] |
| BLLIQ-REENABLE-P02 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | now=D; fuzz compatible L,G; seed D=MAX48 | Success | Same exact transition; inclusive deadline | Covered: [test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition][test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition], [test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition][test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition] |
| BLLIQ-REENABLE-P03 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | D<MAX48; fuzz now in D+1..MAX48; seed D+1,MAX48 | `GracePeriod_Expired(D)` | Unchanged; no committed logs | Covered: [test_givenExpiredGrace_whenReEnabled_reverts][test_givenExpiredGrace_whenReEnabled_reverts], [test_givenEachPermittedRole_whenExpiredGraceEndpoints_thenExactError][test_givenEachPermittedRole_whenExpiredGraceEndpoints_thenExactError] |

## Dependency compatibility

Fixed for this table: Core active: true; Core enabled: true; Local enabled: false; Accounting / events: Unchanged; no committed transition/logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-D04 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Core reports another Kernel; lastTransitionAt nonzero; within grace | `PolicyDependency_KernelMismatch(Core,expectedKernel,actualKernel)` | Covered: [test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch][test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch], [test_givenEachPermittedRole_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch][test_givenEachPermittedRole_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch] |

## Grace deadline overflow

Initialized, locally disabled; otherwise compatible dependencies. Configure G while enabled, disable at L and assert the stored transition timestamp before attempting reEnable. Checked uint48 deadline narrowing is the required behavior: the deadline must fit in uint48. The setter stores a nonzero uint32 duration; the future disable timestamp is not known when it is set.

| ID | Caller | Prior transition L | Grace G | Now | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-N01 | Fuzz ADMIN-only, BURNER_LOANS_ADMIN-only and overlap holders; seed each | Fuzz MAX48-G+1..MAX48 | Configured G in 1..MAX32; seed1,MAX32 | L | `SafeCastOverflowedUintDowncast(48, uint256(L)+uint256(G))` | Unchanged; no committed transition logs | Covered: [test_givenGraceDeadlineOverflow_whenReEnabled_reverts][test_givenGraceDeadlineOverflow_whenReEnabled_reverts], [test_givenEachPermittedRole_whenGraceOverflows_thenExactTypedError][test_givenEachPermittedRole_whenGraceOverflows_thenExactTypedError] |

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
| BLLIQ-REENABLE-L05 | Fuzz all callers | false | false | 0 | 0 | `NeverEnabled()` before authorization; no ROLES call | No lifecycle/accounting change or committed logs | Covered: [test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence][test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence] |

## Payout activation readiness

Core and Inventory remain operational; the selected Payout drifts after the graph was enabled.
The subject is active, locally disabled and has initialized history. For reEnable, use authorized
recovery callers and independently valid grace windows.

| ID | Payout active | Payout enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQ-REENABLE-D09 | true | false | PolicyDependency_NotActive(Payout) | Local state/history and accounting preserved | Covered: [test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry][test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry], [test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry][test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D10 | false | true | PolicyDependency_NotActive(Payout) | Local state/history and accounting preserved | Covered: [test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry][test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D11 | false | false | PolicyDependency_NotActive(Payout) | Local state/history and accounting preserved | Covered: [test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry][test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry] |
| BLLIQ-REENABLE-D12 | true | true | Success after restoring failed Payout state and retrying reEnable | Exact Enabled/Transition events and timestamp; accounting preserved | Covered: [test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry][test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry], [test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry][test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry], [test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry][test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry] |

[test_givenActivatedButNeverEnabled_whenReEnabled_thenHistoryWins]: reEnable.t.sol#L455
[test_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch]: reEnable.t.sol#L169
[test_givenCoreUnavailable_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L496
[test_givenDisabled_whenUnauthorizedReEnables_reverts]: reEnable.t.sol#L124
[test_givenEachPermittedRole_givenCoreReportedKernelChanges_whenReEnabled_thenKernelMismatch]: reEnable.t.sol#L352
[test_givenEachPermittedRole_givenInactive_whenReEnabled_reverts]: reEnable.t.sol#L333
[test_givenEachPermittedRole_givenPayoutPaused_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L473
[test_givenEachPermittedRole_givenSettlementRoleRevoked_whenReEnabled_reverts]: reEnable.t.sol#L373
[test_givenEachPermittedRole_whenExpiredGraceEndpoints_thenExactError]: reEnable.t.sol#L286
[test_givenEachPermittedRole_whenGraceEndpoints_thenExactTransition]: reEnable.t.sol#L251
[test_givenEachPermittedRole_whenGraceOverflows_thenExactTypedError]: reEnable.t.sol#L305
[test_givenEachUnavailableCoreStateAndPermittedRole_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L523
[test_givenEachUnavailableInventoryStateAndPermittedRole_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L577
[test_givenEachUnavailablePayoutState_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L418
[test_givenEnabled_whenAnyCallerReEnables_reverts]: reEnable.t.sol#L137
[test_givenExpiredGraceAndUnavailableCore_whenUnauthorizedReEnables_thenAuthWins]: reEnable.t.sol#L152
[test_givenExpiredGrace_whenReEnabled_reverts]: reEnable.t.sol#L69
[test_givenGraceDeadlineOverflow_whenReEnabled_reverts]: reEnable.t.sol#L97
[test_givenInactive_whenReEnabled_reverts]: reEnable.t.sol#L30
[test_givenInventoryUnavailable_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L550
[test_givenNeverActivated_whenReEnabled_thenInitializationPrecedence]: reEnable.t.sol#L239
[test_givenPayoutUnavailable_whenReEnabled_thenRejectAndRetry]: reEnable.t.sol#L392
[test_givenSettlementRoleRevoked_whenReEnabled_reverts]: reEnable.t.sol#L217
[test_givenWithinGrace_whenPermittedCallerReEnables_thenExactTransition]: reEnable.t.sol#L52
[test_givenZeroTransitionHistory_whenAlreadyEnabled_thenStateWins]: reEnable.t.sol#L328

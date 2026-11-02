# BurnerLoansConfigTimelock.setGracePeriod coverage plan

The concrete setter requires own Kernel activity before inherited local enablement, ADMIN authorization and nonzero-period validation. Same valid periods retain the inherited single-event behavior and do not alter lifecycle history.

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column.

## Domains and notation

Scenario scope `BLCTLGR`: BurnerLoansConfigTimelock.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansConfigTimelock; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock)` before body/input/idempotent work. Own activity precedes local enablement, caller roles, and input or target checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

The immutable Config is Kernel-active. Own Timelock activity is required; enable/reEnable dependency rules are covered in those plans. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTLGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test_givenUnauthorizedCaller_whenPeriodOne_thenRoleError][test_givenUnauthorizedCaller_whenPeriodOne_thenRoleError] |
| BLCTLGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test_givenUnauthorizedCaller_whenPeriodZero_thenRoleError][test_givenUnauthorizedCaller_whenPeriodZero_thenRoleError] |

## Lifecycle

Fixed for this table: Local enabled: false; Accounting / events: Unchanged; before caller/input.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCTLGR-L01 | Fuzz all callers | period=1 | `NotEnabled()` | Covered: [test_givenDisabled_whenPeriodOne_thenStateError][test_givenDisabled_whenPeriodOne_thenStateError] |
| BLCTLGR-L02 | Fuzz all callers | period=0 | `NotEnabled()` | Covered: [test_givenDisabled_whenPeriodZero_thenStateError][test_givenDisabled_whenPeriodZero_thenStateError] |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCTLGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent][test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent]; [test_givenGraceN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |
| BLCTLGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test_givenAdmin_whenPeriodZero_reverts][test_givenAdmin_whenPeriodZero_reverts] |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCTLGR-L03 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfigTimelock) | Unchanged; no body/token/module calls or committed logs | Partial: [test_givenOwnPolicyInactive_whenPeriodSet_reverts][test_givenOwnPolicyInactive_whenPeriodSet_reverts]; test implemented; production error differs from the required lifecycle/operator error |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map every row to its scenario test and boundary seeds; retain production-blocked rows as Partial.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCTLGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test_givenAdmin_whenSamePeriodSet_thenOneEvent][test_givenAdmin_whenSamePeriodSet_thenOneEvent]; [test_givenGraceP01Endpoints_whenBoundarySeedsRun_thenScenarioHolds][test_givenGraceP01Endpoints_whenBoundarySeedsRun_thenScenarioHolds] |

## Admission precedence regressions

TL denotes this timelock. Unchanged includes the queue, lifecycle and custody fields relevant to the action.

| ID | Caller | Local active | Local enabled | Competing fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCTLGR-L04 | Fuzz all callers | false | Fuzz false/true | ROLES code rejects; fuzz full uint32 period | BurnerLoans_PolicyNotActive(TL) | Period, enabled flag, transition timestamp and preserved state unchanged | Covered: [test][test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts] |

[test_givenUnauthorizedCaller_whenPeriodOne_thenRoleError]: ./setGracePeriod.t.sol#L18
[test_givenUnauthorizedCaller_whenPeriodZero_thenRoleError]: ./setGracePeriod.t.sol#L28
[test_givenDisabled_whenPeriodOne_thenStateError]: ./setGracePeriod.t.sol#L38
[test_givenDisabled_whenPeriodZero_thenStateError]: ./setGracePeriod.t.sol#L48
[test_givenAdmin_whenFullWidthPeriodSet_thenOneEvent]: ./setGracePeriod.t.sol#L82
[test_givenGraceN01Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./setGracePeriod.t.sol#L119
[test_givenAdmin_whenPeriodZero_reverts]: ./setGracePeriod.t.sol#L58
[test_givenOwnPolicyInactive_whenPeriodSet_reverts]: ./setGracePeriod.t.sol#L68
[test_givenAdmin_whenSamePeriodSet_thenOneEvent]: ./setGracePeriod.t.sol#L100
[test_givenGraceP01Endpoints_whenBoundarySeedsRun_thenScenarioHolds]: ./setGracePeriod.t.sol#L130
[test_givenPolicyInactive_givenBrokenRoles_whenGraceSet_reverts]: ./setGracePeriod.t.sol#L141

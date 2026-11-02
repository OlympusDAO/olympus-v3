# BurnerLoansSeize.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage mappings below identify the implemented Foundry proofs.

## Domains and notation

Scenario scope `BLLIQGR`: BurnerLoansSeize.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansSeize; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeize)` before body/input/idempotent work. Preserve existing earlier guards; missing or differently reported source checks are required implementation gaps. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

All concrete hook dependencies listed below satisfied; ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test_whenUnauthorizedGraceSetter_revertsBeforeInput](setGracePeriod.t.sol#L48) |
| BLLIQGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test_whenUnauthorizedGraceSetter_revertsBeforeInput](setGracePeriod.t.sol#L48) |

## Lifecycle

| ID | Caller | Core active | Core enabled | Local enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLLIQGR-L01 | Fuzz all callers | true | true | false | period=1 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabled_whenGraceSet_thenPauseWins](setGracePeriod.t.sol#L60) |
| BLLIQGR-L02 | Fuzz all callers | true | true | false | period=0 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabled_whenGraceSet_thenPauseWins](setGracePeriod.t.sol#L60) |
| BLLIQGR-L03 | ADMIN_ROLE holder | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenCoreState_whenGraceSet_thenControllerIndependent](setGracePeriod.t.sol#L69), [test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent](setGracePeriod.t.sol#L116) |
| BLLIQGR-L04 | ADMIN_ROLE holder | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenCoreState_whenGraceSet_thenControllerIndependent](setGracePeriod.t.sol#L69), [test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent](setGracePeriod.t.sol#L116) |
| BLLIQGR-L05 | ADMIN_ROLE holder | false | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenCoreState_whenGraceSet_thenControllerIndependent](setGracePeriod.t.sol#L69), [test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent](setGracePeriod.t.sol#L116) |
| BLLIQGR-L06 | ADMIN_ROLE holder | false | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenCoreState_whenGraceSet_thenControllerIndependent](setGracePeriod.t.sol#L69), [test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent](setGracePeriod.t.sol#L116) |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLLIQGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test_givenCoreState_whenGraceSet_thenControllerIndependent](setGracePeriod.t.sol#L69), [test_whenPeriodIsOne_thenStoredAndEmitted](setGracePeriod.t.sol#L106), [test_whenPeriodIsMaximum_thenStoredAndEmitted](setGracePeriod.t.sol#L111), [test_givenEveryCoreState_whenGraceSetToOne_thenControllerIndependent](setGracePeriod.t.sol#L116), [test_whenPeriodUnchangedFromDefault_thenStoredAndEmitted](setGracePeriod.t.sol#L131) |
| BLLIQGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test_whenGraceIsZero_reverts](setGracePeriod.t.sol#L41) |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLIQGR-L07 | Fuzz all callers | false | Fuzz true/false | BurnerLoans_PolicyNotActive(BurnerLoansSeize) | Unchanged; no body/token/module calls or committed logs | Covered: [test_givenInactiveSubject_whenGraceSet_reverts](setGracePeriod.t.sol#L90) ; [test][test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. This action owns no custody or position state; recovery must preserve Core grants and all canonical positions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLLIQGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test_whenGraceSetToSameValue_thenStillEmits](setGracePeriod.t.sol#L23), [test_whenPeriodIsOne_thenStoredAndEmitted](setGracePeriod.t.sol#L106), [test_whenPeriodIsMaximum_thenStoredAndEmitted](setGracePeriod.t.sol#L111), [test_whenPeriodUnchangedFromDefault_thenStoredAndEmitted](setGracePeriod.t.sol#L131) |

[test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L136

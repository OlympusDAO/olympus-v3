# BurnerLoansCollateral.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Test mappings name the passing proofs.

## Domains and notation

Lifecycle and framework tests live in function-specific files. Their shared `BurnerLoansCollateralTest` fixture preserves real debt, custody, receipts and an unrelated borrower.

Scenario scope `BLCOLGR`: BurnerLoansCollateral.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansCollateral; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCollateral)` before body/input/idempotent work. Preserve existing earlier guards; missing or differently reported source checks are required implementation gaps. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

All concrete hook dependencies listed below satisfied; ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOLGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test_whenUnauthorizedCallerSetsValidPeriod_reverts](setGracePeriod.t.sol#L81) |
| BLCOLGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test_whenUnauthorizedCallerSetsZero_reverts](setGracePeriod.t.sol#L88) |

## Lifecycle

| ID | Caller | Core active | Core enabled | Local enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCOLGR-L01 | Fuzz all callers | true | true | false | period=1 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabled_whenValidPeriod_reverts](setGracePeriod.t.sol#L95), [test_givenDisabledAfterEnable_whenGraceSet_thenPauseWins](setGracePeriod.t.sol#L144) |
| BLCOLGR-L02 | Fuzz all callers | true | true | false | period=0 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabled_whenZeroPeriod_reverts](setGracePeriod.t.sol#L103), [test_givenDisabledAfterEnable_whenGraceSet_thenPauseWins](setGracePeriod.t.sol#L144) |
| BLCOLGR-L03 | ADMIN_ROLE holder | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges](setGracePeriod.t.sol#L23), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |
| BLCOLGR-L04 | ADMIN_ROLE holder | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges](setGracePeriod.t.sol#L23), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |
| BLCOLGR-L05 | ADMIN_ROLE holder | false | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges](setGracePeriod.t.sol#L23), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |
| BLCOLGR-L06 | ADMIN_ROLE holder | false | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges](setGracePeriod.t.sol#L23), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOLGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test_givenIndependentCoreState_whenGraceSet_thenOnlyPeriodChanges](setGracePeriod.t.sol#L23), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |
| BLCOLGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test_whenAdminSetsZero_reverts](setGracePeriod.t.sol#L111) |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOLGR-L07 | Fuzz all callers | false | Fuzz true/false | BurnerLoans_PolicyNotActive(BurnerLoansCollateral) | Unchanged; no body/token/module calls or committed logs | Covered: [test_givenInactive_whenAdminSetsPeriod_reverts](setGracePeriod.t.sol#L120) ; [test][test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. This action owns no custody or position state; recovery must preserve Core grants and all canonical positions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCOLGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test_whenGraceEqualsCurrentValue_thenEventStillEmitted](setGracePeriod.t.sol#L42), [test_whenBoundaryAndCoreStateSeedsUsed_thenPeriodStored](setGracePeriod.t.sol#L59) |

[test_givenInactiveAndDisabled_whenAnyCallerSetsGrace_reverts]: setGracePeriod.t.sol#L155

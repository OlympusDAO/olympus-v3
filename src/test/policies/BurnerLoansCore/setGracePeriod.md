# BurnerLoansCore.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope `BLCOREGR`: BurnerLoansCore.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansCore; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansCore)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

DepositManager, Inventory, Config and Custody are active same-Kernel policies; DepositManager and Inventory are enabled; Risk is selected with deployed code. Config enablement is not checked; Custody and Risk have no local Enabler. Core must be Kernel-active for enable/reEnable. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOREGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test][test_givenUnauthorized_whenGraceSet_reverts] |
| BLCOREGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test][test_givenUnauthorized_whenGraceSet_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCOREGR-L01 | Fuzz ADMIN_ROLE holder | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenAdmin_whenGraceSet] |
| BLCOREGR-L02 | Fuzz ADMIN_ROLE holder | true | false | NotEnabled() | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenGraceSet_reverts], [test][test_givenActiveDisabled_whenGraceSet_reverts] |
| BLCOREGR-L03 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenGraceSet_reverts] |
| BLCOREGR-L04 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenUnavailableCore_whenGraceSet_reverts] |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOREGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test][test_givenAdmin_whenGraceSet], [test][test_whenGracePeriodBoundarySeeds] |
| BLCOREGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test][test_whenZeroGraceSet_reverts] |

## Callbacks and reentrancy

Fixed for this table: Local enabled: true; Accounting / events: Unchanged.

| ID | Caller | Callback / nested call | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLCOREGR-C01 | ADMIN_ROLE holder | period=1; Core settlement guard entered | `ReentrancyGuardReentrantCall()` | Covered: [test][test_givenBusyCore_whenGraceSet_reverts] |

## Own policy activity

The lifecycle matrix above covers independent local activity/enablement. Disabled-state admission precedes role/input checks; active+enabled is required for mutation. Missing own activity checks remain implementation gaps.

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to implemented tests.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCOREGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test][test_givenSamePeriod_whenGraceSet] |

[test_givenAdmin_whenGraceSet]: setGracePeriod.t.sol#L20
[test_givenBusyCore_whenGraceSet_reverts]: setGracePeriod.t.sol#L91
[test_givenSamePeriod_whenGraceSet]: setGracePeriod.t.sol#L42
[test_givenUnauthorized_whenGraceSet_reverts]: setGracePeriod.t.sol#L58
[test_givenUnavailableCore_whenGraceSet_reverts]: setGracePeriod.t.sol#L66
[test_whenGracePeriodBoundarySeeds]: setGracePeriod.t.sol#L35
[test_whenZeroGraceSet_reverts]: setGracePeriod.t.sol#L85

[test_givenActiveDisabled_whenGraceSet_reverts]: setGracePeriod.t.sol#L78

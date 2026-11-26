# BurnerLoansYieldClaimerTask.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-GRACE` identifies this contract/function.

Inherited setter exception: the same valid nonzero grace period emits one `GracePeriodSet` event without changing lifecycle state or its transition timestamp.

Own-policy admission: require Kernel-active BurnerLoansYieldClaimerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Core is Kernel-active and this Claimer holds BL_YIELD_CLAIMER_ROLE. Core enablement is unrelated to this numeric setter; Claimer own activity is required. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-GRACE-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test][test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts] |
| BLYC-GRACE-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test][test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts] |
| BLYC-GRACE-A03 | Fuzz ADMIN_ROLE holder | Task Kernel-active and enabled; changed period fuzz1..MAX32, excluding current period; seed1,MAX32 | Success | Exact gracePeriod and GracePeriodSet(period); enabled flag, transition timestamp, accounting and other settings unchanged | Covered: [test][test_givenArbitraryAdmin_whenGraceSet] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLYC-GRACE-L01 | Fuzz all callers | true | false | true | true | period=1 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test][test_givenDisabled_revertsBeforeAuthorizationOrValidation] |
| BLYC-GRACE-L02 | Fuzz all callers | false | false | true | true | period=1 | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; before caller/input | Covered: [test][test_givenInactiveDisabled_revertsBeforeAuthorizationOrValidation] |
| BLYC-GRACE-L03 | Fuzz all callers | true | false | true | true | period=0 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test][test_givenDisabled_revertsBeforeAuthorizationOrValidation] |
| BLYC-GRACE-L04 | Fuzz all callers | false | false | true | true | period=0 | `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` | Unchanged; before caller/input | Covered: [test][test_givenInactiveDisabled_revertsBeforeAuthorizationOrValidation] |
| BLYC-GRACE-L05 | ADMIN_ROLE holder | true | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenDifferentValidPeriod_setsPeriod], [test][test_givenArbitraryAdmin_whenGraceSet] |
| BLYC-GRACE-L06 | ADMIN_ROLE holder | false | true | true | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenGraceSet_reverts] |
| BLYC-GRACE-L07 | ADMIN_ROLE holder | true | true | true | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenArbitraryAdmin_whenGraceSet] |
| BLYC-GRACE-L08 | ADMIN_ROLE holder | false | true | true | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenGraceSet_reverts] |
| BLYC-GRACE-L09 | ADMIN_ROLE holder | true | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenArbitraryAdmin_whenGraceSet] |
| BLYC-GRACE-L10 | ADMIN_ROLE holder | false | true | false | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenGraceSet_reverts] |
| BLYC-GRACE-L11 | ADMIN_ROLE holder | true | true | false | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenArbitraryAdmin_whenGraceSet] |
| BLYC-GRACE-L12 | ADMIN_ROLE holder | false | true | false | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactivePolicy_whenGraceSet_reverts] |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-GRACE-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test][test_givenDifferentValidPeriod_setsPeriod], [test][test_whenGracePeriodBoundaryUsed_storesExactPeriod], [test][test_givenArbitraryAdmin_whenGraceSet], [test][test_whenPeriodSeeds] |
| BLYC-GRACE-N02 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test][test_givenZeroPeriod_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Unchanged grace period

Own policy active/enabled; ADMIN; valid nonzero duration. Shared ReEnablerGracePeriod is unchanged.

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-GRACE-P02 | Fuzz ADMIN holder | Current period; fuzz1..MAX32; seed1,MAX32 | Success | One GracePeriodSet(period); period/enablement/transition timestamp unchanged | Covered: [test][test_givenCurrentPeriod_emitsEvent], [test][test_whenPeriodSeeds] |

Retired IDs: BLYC-GRACE-P01. Replacement cases isolate supported outcomes; removed duplicates add no proof.

[test_givenArbitraryAdmin_whenGraceSet]: setGracePeriod.t.sol#L148
[test_givenCurrentPeriod_emitsEvent]: setGracePeriod.t.sol#L115
[test_givenDifferentValidPeriod_setsPeriod]: setGracePeriod.t.sol#L79
[test_givenDisabled_revertsBeforeAuthorizationOrValidation]: setGracePeriod.t.sol#L18
[test_givenEnabled_whenUnauthorizedCallerSetsPeriod_reverts]: setGracePeriod.t.sol#L53
[test_givenInactivePolicy_whenGraceSet_reverts]: setGracePeriod.t.sol#L131
[test_givenZeroPeriod_reverts]: setGracePeriod.t.sol#L68
[test_whenGracePeriodBoundaryUsed_storesExactPeriod]: setGracePeriod.t.sol#L103
[test_whenPeriodSeeds]: setGracePeriod.t.sol#L167

[test_givenInactiveDisabled_revertsBeforeAuthorizationOrValidation]: setGracePeriod.t.sol#L33

# BurnerLoansConfig.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope `BLCFGGR`: BurnerLoansConfig.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansConfig; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Core is active, advertises IBurnerLoansCore/IEnabler, reports the expected OHM and selects this Config. Inventory is nonzero, active, same-Kernel, advertises IBurnerLoansInventory and reports the same OHM and Core. Core/Inventory enablement does not gate this numeric setter; Config own activity is required. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFGGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| BLCFGGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLCFGGR-L01 | Fuzz all callers | true | false | true | true | period=1 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test][test_givenDisabled_whenGraceChanged_reverts] |
| BLCFGGR-L02 | Fuzz all callers | false | false | true | true | period=1 | `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` | Unchanged; before caller/input | Covered: [test][test_givenInactiveDisabled_whenGraceChanged_reverts] |
| BLCFGGR-L03 | Fuzz all callers | true | false | true | true | period=0 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test][test_givenDisabled_whenGraceChanged_reverts] |
| BLCFGGR-L04 | Fuzz all callers | false | false | true | true | period=0 | `BurnerLoans_PolicyNotActive(BurnerLoansConfig)` | Unchanged; before caller/input | Covered: [test][test_givenInactiveDisabled_whenGraceChanged_reverts] |
| BLCFGGR-L05 | ADMIN_ROLE holder | true | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenActiveEnabled_whenValidGraceSet] |
| BLCFGGR-L06 | ADMIN_ROLE holder | false | true | true | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactiveEnabled_whenGraceChanged_reverts] |
| BLCFGGR-L07 | ADMIN_ROLE holder | true | true | true | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenActiveEnabled_whenValidGraceSet] |
| BLCFGGR-L08 | ADMIN_ROLE holder | false | true | true | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactiveEnabled_whenGraceChanged_reverts] |
| BLCFGGR-L09 | ADMIN_ROLE holder | true | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenActiveEnabled_whenValidGraceSet] |
| BLCFGGR-L10 | ADMIN_ROLE holder | false | true | false | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactiveEnabled_whenGraceChanged_reverts] |
| BLCFGGR-L11 | ADMIN_ROLE holder | true | true | false | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test][test_givenActiveEnabled_whenValidGraceSet] |
| BLCFGGR-L12 | ADMIN_ROLE holder | false | true | false | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test][test_givenInactiveEnabled_whenGraceChanged_reverts] |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLCFGGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test][test_givenActiveEnabled_whenValidGraceSet], [test][test_whenGraceBoundariesAreSeeded] |
| BLCFGGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test][test_whenGraceIsZero_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLCFGGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test][test_whenSameGraceSet], [test][test_whenGraceBoundariesAreSeeded] |

[test_whenCallerIsNotAdmin_reverts]: ./setGracePeriod.t.sol#L19
[test_givenDisabled_whenGraceChanged_reverts]: ./setGracePeriod.t.sol#L29
[test_givenInactiveEnabled_whenGraceChanged_reverts]: ./setGracePeriod.t.sol#L59
[test_whenGraceIsZero_reverts]: ./setGracePeriod.t.sol#L72
[test_givenActiveEnabled_whenValidGraceSet]: ./setGracePeriod.t.sol#L81
[test_whenSameGraceSet]: ./setGracePeriod.t.sol#L104
[test_whenGraceBoundariesAreSeeded]: ./setGracePeriod.t.sol#L119

[test_givenInactiveDisabled_whenGraceChanged_reverts]: setGracePeriod.t.sol#L44

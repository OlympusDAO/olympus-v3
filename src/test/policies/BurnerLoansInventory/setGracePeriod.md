# BurnerLoansInventory.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column with reciprocal scenario IDs in the linked tests.

## Domains and notation

Scenario scope `BLINVGR`: BurnerLoansInventory.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansInventory; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

The immutable Core is active and reports this Kernel. Facility operational state does not gate this numeric setter; Inventory own activity is required. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINVGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Covered: [test_givenUnauthorizedCaller_reverts][test_givenUnauthorizedCaller_reverts] |
| BLINVGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Covered: [test_givenUnauthorizedCaller_whenZeroPeriod_reverts][test_givenUnauthorizedCaller_whenZeroPeriod_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLINVGR-L01 | Fuzz all callers | true | false | true | true | period=1 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabledInventory_whenGraceSet_reverts][test_givenDisabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L02 | Fuzz all callers | false | false | true | true | period=1 | `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` | Unchanged; before caller/input | Covered: [test_givenInactiveDisabledInventory_whenGraceSet_reverts][test_givenInactiveDisabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L03 | Fuzz all callers | true | false | true | true | period=0 | `NotEnabled()` | Unchanged; before caller/input | Covered: [test_givenDisabledInventory_whenGraceSet_reverts][test_givenDisabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L04 | Fuzz all callers | false | false | true | true | period=0 | `BurnerLoans_PolicyNotActive(BurnerLoansInventory)` | Unchanged; before caller/input | Covered: [test_givenInactiveDisabledInventory_whenGraceSet_reverts][test_givenInactiveDisabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L05 | ADMIN_ROLE holder | true | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenActiveEnabledInventory_whenGraceSet_succeeds][test_givenActiveEnabledInventory_whenGraceSet_succeeds]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L06 | ADMIN_ROLE holder | false | true | true | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test_givenInactiveEnabledInventory_whenGraceSet_reverts][test_givenInactiveEnabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L07 | ADMIN_ROLE holder | true | true | true | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenActiveEnabledInventory_whenGraceSet_succeeds][test_givenActiveEnabledInventory_whenGraceSet_succeeds]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L08 | ADMIN_ROLE holder | false | true | true | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test_givenInactiveEnabledInventory_whenGraceSet_reverts][test_givenInactiveEnabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L09 | ADMIN_ROLE holder | true | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenActiveEnabledInventory_whenGraceSet_succeeds][test_givenActiveEnabledInventory_whenGraceSet_succeeds]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L10 | ADMIN_ROLE holder | false | true | false | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test_givenInactiveEnabledInventory_whenGraceSet_reverts][test_givenInactiveEnabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L11 | ADMIN_ROLE holder | true | true | false | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Covered: [test_givenActiveEnabledInventory_whenGraceSet_succeeds][test_givenActiveEnabledInventory_whenGraceSet_succeeds]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-L12 | ADMIN_ROLE holder | false | true | false | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansInventory) | Unchanged; no input validation, module/token calls, setter events or committed logs | Covered: [test_givenInactiveEnabledInventory_whenGraceSet_reverts][test_givenInactiveEnabledInventory_whenGraceSet_reverts]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLINVGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Covered: [test_givenValidPeriod_setsPeriod][test_givenValidPeriod_setsPeriod]; [test_givenMaximumPeriod_setsPeriod][test_givenMaximumPeriod_setsPeriod]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |
| BLINVGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Covered: [test_givenZeroPeriod_reverts][test_givenZeroPeriod_reverts] |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLINVGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Covered: [test_givenSamePeriod_whenSet_emitsOnce][test_givenSamePeriod_whenSet_emitsOnce]; [test_whenGraceAndLifecycleSeeds][test_whenGraceAndLifecycleSeeds] |

## Validation

The mapped tests run in the focused Inventory suite. [Shared fixtures](BurnerLoansInventoryTest.sol) isolate Core for unit tests; modular tests exercise real Core. The [stateful campaign](BurnerLoansInventory.invariant.t.sol) covers one provider and successful accounting/lifecycle sequences; token failures and multiple providers have focused tests. This is not a repository-wide validation claim.

[test_givenActiveEnabledInventory_whenGraceSet_succeeds]: setGracePeriod.t.sol#L133
[test_givenDisabledInventory_whenGraceSet_reverts]: setGracePeriod.t.sol#L89
[test_givenInactiveEnabledInventory_whenGraceSet_reverts]: setGracePeriod.t.sol#L115
[test_givenMaximumPeriod_setsPeriod]: setGracePeriod.t.sol#L69
[test_givenSamePeriod_whenSet_emitsOnce]: setGracePeriod.t.sol#L163
[test_givenUnauthorizedCaller_reverts]: setGracePeriod.t.sol#L25
[test_givenUnauthorizedCaller_whenZeroPeriod_reverts]: setGracePeriod.t.sol#L154
[test_givenValidPeriod_setsPeriod]: setGracePeriod.t.sol#L58
[test_givenZeroPeriod_reverts]: setGracePeriod.t.sol#L43
[test_whenGraceAndLifecycleSeeds]: setGracePeriod.t.sol#L186

[test_givenInactiveDisabledInventory_whenGraceSet_reverts]: setGracePeriod.t.sol#L102

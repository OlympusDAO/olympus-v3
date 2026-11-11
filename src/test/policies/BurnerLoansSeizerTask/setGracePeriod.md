# BurnerLoansSeizerTask.setGracePeriod coverage plan

Source: [setGracePeriod](../../../bases/ReEnablerGracePeriod.sol#L74). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope `BLSEIZGR`: BurnerLoansSeizerTask.setGracePeriod.

Inherited behavior is intentional: setting the same valid nonzero grace period succeeds and emits GracePeriodSet once. It is not an ordinary configuration no-op. Preserve the underlying ReEnablerGracePeriod implementation; neither equality rejection nor event suppression is required.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Apply existing reentrancy guards, own Kernel activity, required local enablement, then caller authorization. Successful body scenarios assume Local active=true, except explicit admission failures.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Scenario setup

Core and the selected Seize action are Kernel-active. Their local enablement does not gate this numeric setter; SeizerTask own activity is required. ROLES initialized. No caller label below stands for an unspecified permitted set. Unauthorized fuzzing excludes all holders of the named roles. `deadline=lastTransitionAt+gracePeriod`.

## Authorization

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZGR-A01 | Fuzz caller excluding all ADMIN_ROLE holders | period=1 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged | Unmapped |
| BLSEIZGR-A02 | Fuzz caller excluding all ADMIN_ROLE holders | period=0 | `ROLES_RequireRole(ADMIN_ROLE)` | Unchanged; authorization before numeric input | Unmapped |

## Lifecycle

| ID | Caller | Local active | Local enabled | Core active | Core enabled | Lifecycle state / history | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLSEIZGR-L01 | Fuzz all callers | true | false | true | true | period=1 | `NotEnabled()` | Unchanged; before caller/input | Unmapped |
| BLSEIZGR-L02 | Fuzz all callers | false | false | true | true | period=1 | `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` | Unchanged; before caller/input | Unmapped |
| BLSEIZGR-L03 | Fuzz all callers | true | false | true | true | period=0 | `NotEnabled()` | Unchanged; before caller/input | Unmapped |
| BLSEIZGR-L04 | Fuzz all callers | false | false | true | true | period=0 | `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` | Unchanged; before caller/input | Unmapped |
| BLSEIZGR-L05 | ADMIN_ROLE holder | true | true | true | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Unmapped |
| BLSEIZGR-L06 | ADMIN_ROLE holder | false | true | true | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Unmapped; required own-policy activity error |
| BLSEIZGR-L07 | ADMIN_ROLE holder | true | true | true | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Unmapped |
| BLSEIZGR-L08 | ADMIN_ROLE holder | false | true | true | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Unmapped; required own-policy activity error |
| BLSEIZGR-L09 | ADMIN_ROLE holder | true | true | false | true | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Unmapped |
| BLSEIZGR-L10 | ADMIN_ROLE holder | false | true | false | true | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Unmapped; required own-policy activity error |
| BLSEIZGR-L11 | ADMIN_ROLE holder | true | true | false | false | other dependencies ready; period=1 | `Success` | gracePeriod=input; GracePeriodSet(input); transition timestamp unchanged | Unmapped |
| BLSEIZGR-L12 | ADMIN_ROLE holder | false | true | false | false | other dependencies ready; period=1 | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no input validation, module/token calls, setter events or committed logs | Unmapped; required own-policy activity error |

## Numeric boundaries and arithmetic

The input is a uint32 duration, not an absolute expiry. Every nonzero representable duration is currently accepted, including MAX32; values above MAX32 cannot be supplied through the typed API. `_setGracePeriod` does not add it to a timestamp. `lastTransitionAt` is replaced by a later disable, so rejecting a duration against the current transition cannot prevent that future addition from overflowing. The reEnable plan requires SafeCastOverflowedUintDowncast(48,D) if the future deadline D=uint256(L)+uint256(G) cannot fit in uint48 (implemented in the concrete Burner Loans override; shared base unchanged), with no lifecycle transition or committed logs.

Fixed for this table: Core active: true; Core enabled: true; Local enabled: true.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZGR-N01 | ADMIN_ROLE holder | period fuzz 1..MAX32; seed 1, currentPeriod, MAX32 | `Success` | gracePeriod=input; GracePeriodSet(input); lastTransitionAt unchanged | Unmapped |
| BLSEIZGR-I01 | ADMIN_ROLE holder | period=0 | `GracePeriod_ZeroPeriod()` | Unchanged | Unmapped |

## Shared assertions

Construct only reachable dependency drift: deactivation/local disable/migration after successful binding. Restoration then retry proves recovery, not only initial failure. Getter assertions include exact enabled/timestamp/grace values. Core callback guard enforcement is specific to Core; do not add cross-contract sessions.

Co-located API assertions: `isEnabled`, `lastTransitionAt`, `gracePeriod`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Test organization

[setGracePeriod.t.sol](./setGracePeriod.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Same grace period

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLSEIZGR-P01 | Fuzz ADMIN_ROLE holder | period equals stored gracePeriod; fuzz 1..MAX32; seed 1,MAX32 | Success | GracePeriodSet(period) once; stored period unchanged; isEnabled and lastTransitionAt unchanged; positions/obligations/balances unchanged | Unmapped |

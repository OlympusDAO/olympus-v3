# BurnerLoansYieldClaimerTask.setMinimumGasToAttempt coverage plan

Source: [setMinimumGasToAttempt](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L296). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-MINIMUM-GAS` identifies this contract/function.

Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each: independently fuzz a nonzero caller holding ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansYieldClaimerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE, local enablement is independent; own policy activity is enforced before role/input validation; inputuint32. Accepted: gasReserve<gas<=MAX32. Required validation precedes same-value no-op.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Setter caller classes are ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, and holders of both; seed each partition independently of inputs and lifecycle. Unauthorized callers hold neither role. Own Kernel activity is required before role/input validation; local disablement and Core lifecycle do not gate this setter. Only the selected field changes.

## Authorization

Own policy active; ROLES initialized. Rejected calls preserve state/events; admitted changed values emit only the named setter event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-MINIMUM-GAS-A01 | Fuzz caller holding neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE; exclude every holder of either | Valid/invalid/same input | NotAuthorised before input checks | Covered: [test][test_whenUnauthorizedCallerSetsMinimumGas_reverts] |
| BLYC-MINIMUM-GAS-A02 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Fuzz minimum in gasReserve+1..MAX32 excluding current minimum; seed reserve+1,MAX32; task enabled, disabled or re-enabled | Store exact threshold and emit MinimumGasToAttemptSet once; reserve, execution budget, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-MINIMUM-GAS-A03 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Fuzz minimum in gasReserve+1..MAX32 excluding current minimum; seed reserve+1,MAX32; task enabled, disabled or re-enabled | Store exact threshold and emit MinimumGasToAttemptSet once; reserve, execution budget, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-MINIMUM-GAS-A04 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Fuzz minimum in gasReserve+1..MAX32 excluding current minimum; seed reserve+1,MAX32; task enabled, disabled or re-enabled | Store exact threshold and emit MinimumGasToAttemptSet once; reserve, execution budget, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-MINIMUM-GAS-I01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | minimum fuzz0..gasReserve; seed0,1,reserve-1,reserve; MAX32 is covered as valid | `BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt()` | Covered: [test][test_whenMinimumGasDoesNotExceedReserve_reverts], [test][test_whenMinimumGasBoundaryIsInvalid_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-MINIMUM-GAS-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Different accepted value, endpoints exact | Store exact input, field setterevent | Other gas settings/cursor/positions unchanged | Covered: [test][test_whenPermittedCallerSetsValidMinimumGas_updatesValue], [test][test_whenMinimumGasBoundariesSet_updatesValue] |
| BLYC-MINIMUM-GAS-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Same accepted value | Idempotent return | No setterevent | Covered: [test][test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp] |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-MINIMUM-GAS-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no body/token/module calls or committed logs | Covered: [test][test_givenInactivePolicy_whenSetting_reverts] |

## Shared assertions

Gas-settings transitions must preserve reserve>=100000 and minimum>reserve. Test valid update order and reverse order rejection, including MAX32 minimum then reserveMAX32−1.

Co-located API assertions: `minimumGasToAttempt`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenInactivePolicy_whenSetting_reverts]: setMinimumGasToAttempt.t.sol#L152
[test_whenAuthorizedRoleAndLocalStateSeeds]: setMinimumGasToAttempt.t.sol#L173
[test_whenMinimumGasBoundariesSet_updatesValue]: setMinimumGasToAttempt.t.sol#L115
[test_whenMinimumGasBoundaryIsInvalid_reverts]: setMinimumGasToAttempt.t.sol#L57
[test_whenMinimumGasDoesNotExceedReserve_reverts]: setMinimumGasToAttempt.t.sol#L34
[test_whenPermittedCallerSetsCurrentMinimumGas_isNoOp]: setMinimumGasToAttempt.t.sol#L132
[test_whenPermittedCallerSetsValidMinimumGas_updatesValue]: setMinimumGasToAttempt.t.sol#L88
[test_whenUnauthorizedCallerSetsMinimumGas_reverts]: setMinimumGasToAttempt.t.sol#L14

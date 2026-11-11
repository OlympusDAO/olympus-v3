# BurnerLoansYieldClaimerTask.setGasReserve coverage plan

Source: [setGasReserve](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L311). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-GAS-RESERVE` identifies this contract/function.

Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each: independently fuzz a nonzero caller holding ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansYieldClaimerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE, local enablement is independent; own policy activity is enforced before role/input validation; inputuint32. Accepted: 100000<=gas<minimumGasToAttempt. Required validation precedes same-value no-op.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Setter caller classes are ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, and holders of both; seed each partition independently of inputs and lifecycle. Unauthorized callers hold neither role. Own Kernel activity is required before role/input validation; local disablement and Core lifecycle do not gate this setter. Only the selected field changes.

## Authorization

Own policy active; ROLES initialized. Rejected calls preserve state/events; admitted changed values emit only the named setter event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-GAS-RESERVE-A01 | Fuzz caller holding neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE; exclude every holder of either | Valid/invalid/same input | NotAuthorised before input checks | Covered: [test][test_whenUnauthorizedCallerSetsReserve_reverts] |
| BLYC-GAS-RESERVE-A02 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Fuzz reserve in 100000..minimumGasToAttempt-1 excluding current reserve; seed100000,threshold-1; task enabled, disabled or re-enabled | Store exact reserve and emit GasReserveSet once; other settings, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-GAS-RESERVE-A03 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Fuzz reserve in 100000..minimumGasToAttempt-1 excluding current reserve; seed100000,threshold-1; task enabled, disabled or re-enabled | Store exact reserve and emit GasReserveSet once; other settings, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-GAS-RESERVE-A04 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Fuzz reserve in 100000..minimumGasToAttempt-1 excluding current reserve; seed100000,threshold-1; task enabled, disabled or re-enabled | Store exact reserve and emit GasReserveSet once; other settings, cursors and accounting unchanged | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |

## Invalid inputs

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-GAS-RESERVE-I01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | reserve fuzz0..99999 or minimumGasToAttempt..MAX32; seed0,1,99999,threshold,threshold+1,MAX32 | `BurnerLoansYieldClaimer_InvalidGasReserve()` | Covered: [test][test_whenPermittedCallerSetsReserveBelowMinimum_reverts], [test][test_whenReserveReachesThreshold_reverts], [test][test_whenReserveBoundaryIsInvalid_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-GAS-RESERVE-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Different accepted value, endpoints exact | Store exact input, field setterevent | Other gas settings/cursor/positions unchanged | Covered: [test][test_whenPermittedCallerSetsValidReserve_updatesValue], [test][test_whenReserveBoundariesSet_updatesValue], [test][test_givenHigherReserve_whenMinimumIsRestored] |
| BLYC-GAS-RESERVE-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | Same accepted value | Idempotent return | No setterevent | Covered: [test][test_whenPermittedCallerSetsCurrentReserve_isNoOp] |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-GAS-RESERVE-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no body/token/module calls or committed logs | Covered: [test][test_givenInactivePolicy_whenSetting_reverts] |

## Shared assertions

Gas-settings transitions must preserve reserve>=100000 and minimum>reserve. Test valid update order and reverse order rejection, including MAX32 minimum then reserveMAX32−1.

Co-located API assertions: `gasReserve`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

[test_givenHigherReserve_whenMinimumIsRestored]: setGasReserve.t.sol#L210
[test_givenInactivePolicy_whenSetting_reverts]: setGasReserve.t.sol#L171
[test_whenAuthorizedRoleAndLocalStateSeeds]: setGasReserve.t.sol#L192
[test_whenPermittedCallerSetsCurrentReserve_isNoOp]: setGasReserve.t.sol#L151
[test_whenPermittedCallerSetsReserveBelowMinimum_reverts]: setGasReserve.t.sol#L36
[test_whenPermittedCallerSetsValidReserve_updatesValue]: setGasReserve.t.sol#L108
[test_whenReserveBoundariesSet_updatesValue]: setGasReserve.t.sol#L136
[test_whenReserveBoundaryIsInvalid_reverts]: setGasReserve.t.sol#L82
[test_whenReserveReachesThreshold_reverts]: setGasReserve.t.sol#L59
[test_whenUnauthorizedCallerSetsReserve_reverts]: setGasReserve.t.sol#L16

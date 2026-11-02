# BurnerLoansSeizerTask.setScanLimits coverage plan

Source: [setScanLimits](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L178). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-SCAN-LIMITS` identifies this contract/function.

Implemented same-value rule: unchanged parameters return without setter writes/events after the concrete checks before equality. Changing-value rows exclude the current value; downstream checks reached only after equality are tested separately.

Fuzz permitted role caller: independently fuzz a nonzero caller holding ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansSeizerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN or BL admin, local enablement is independent; own policy activity is enforced before role/input validation; check:uint16, seize:uint8. Accepted 1<=check<=MAX16;1<=seize<=MAX8;seize<=check. Input types define maxima; there are no additional 500/50 ceilings. Practical settings follow the gas budget and measured workload.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SCAN-LIMITS-A01 | Fuzz caller with neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE; exclude all holders of either | Valid/invalid limits | NotAuthorised | Covered: [test][test_whenCallerHasNeitherRole_whenScanLimitsSet_reverts] |
| BLSEIZ-SCAN-LIMITS-A02 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenLimitsSet], [test][test_whenRolesAndFullWidthBoundariesSeeded] |
| BLSEIZ-SCAN-LIMITS-A03 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenLimitsSet], [test][test_whenRolesAndFullWidthBoundariesSeeded] |
| BLSEIZ-SCAN-LIMITS-A04 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Valid changed inputs; enabled/disabled; type maxima seeded | Success; exact getter/event | Covered: [test][test_givenPermittedCaller_whenLimitsSet], [test][test_whenRolesAndFullWidthBoundariesSeeded] |

## Successful execution

Fixed for this table: Accounting / events: ScanLimitsSet; seed1/1,501/51,MAX16/MAX8 and neighbors.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SCAN-LIMITS-P01 | Fuzz permitted role caller | check1..MAX16,seize1..min(MAX8,check); changed tuple | Store exact changed limits; emit once | Covered: [test][test_givenPermittedCaller_whenLimitsSet] |

Co-located API assertions: `maxBorrowersToCheck`, `maxBorrowersToSeize`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-SCAN-LIMITS-P02 | Fuzz ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holder | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansSeizerTask) | Unchanged; no body/token/module calls or committed logs | Partial: [test][test_givenInactiveTask_whenLimitsSet_reverts]; other permitted caller partitions remain planned |

## Test organization

[setScanLimits.t.sol](./setScanLimits.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Same configuration value

| ID | Caller | Proposed value | Execution | Effects | Test |
| --- | --- | --- | --- | --- |--- |
| BLSEIZ-SCAN-LIMITS-P03 | Fuzz ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE holder; guarantee exclusive and overlap seeds | Exactly current complete value; fuzz the valid domain defined above, including its explicit boundary seeds | No-op after required validation | No setter writes/events; positions, obligations, authority and balances unchanged | Partial: [test][test_whenLimitsUnchanged_thenNoEvent]; other permitted caller partitions remain planned |

## Invalid scan bounds

Local active=true; local enablement independent. Isolate each field failure; MAX16/MAX8 are type maxima. N03/N05 now demonstrate successful values beyond the former ceilings.

| ID | Caller | maxBorrowersToCheck_ | maxBorrowersToSeize_ | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-SCAN-LIMITS-N02 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | check=0 | Fuzz seize1..MAX8 | BurnerLoansSeizer_InvalidScanLimits(0,seize) | Unchanged; no logs | Partial: [test][test_whenCheckLimitZero_reverts], [test][test_whenInvalidBoundariesSeeded_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-SCAN-LIMITS-N03 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | Fuzz check501..MAX16; seed501,MAX16 | Valid seize1..MAX8 | Success | Store exact limits; emit once | Covered: [test][test_givenPermittedCaller_whenLimitsSet], [test][test_whenRolesAndFullWidthBoundariesSeeded] |
| BLSEIZ-SCAN-LIMITS-N04 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | Fuzz check1..MAX16; seed1,MAX16 | seize=0 | BurnerLoansSeizer_InvalidScanLimits(check,0) | Unchanged; no logs | Partial: [test][test_whenSeizureLimitZero_reverts], [test][test_whenInvalidBoundariesSeeded_reverts]; other permitted caller partitions remain planned |
| BLSEIZ-SCAN-LIMITS-N05 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | check>=seize, up to MAX16 | Fuzz seize51..MAX8; seed51,MAX8 | Success | Store exact limits; emit once | Covered: [test][test_givenPermittedCaller_whenLimitsSet], [test][test_whenRolesAndFullWidthBoundariesSeeded] |
| BLSEIZ-SCAN-LIMITS-N06 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | Fuzz check1..254; seed1,254 | Fuzz seize check+1..MAX8; seed check+1,MAX8 | BurnerLoansSeizer_InvalidScanLimits(check,seize) | Unchanged; no logs | Partial: [test][test_whenSeizureLimitExceedsCheckLimit_reverts], [test][test_whenInvalidBoundariesSeeded_reverts]; other permitted caller partitions remain planned |

Retired IDs: BLSEIZ-SCAN-LIMITS-N01. Replacement cases isolate supported outcomes; removed duplicates add no proof.

## Measured gas breakpoints

Run the integration benchmark with deployment bytecode:

```sh
FOUNDRY_PROFILE=deploy FOUNDRY_SRC=src/policies/burnerloans \
FOUNDRY_TEST=src/test/policies/BurnerLoansSeizerTask/integration \
forge test --match-contract BurnerLoansSeizerTaskScanGasTest -vv
```

The fixture uses real Core/FLOAN/Risk/Inventory/DepositManager/Payout/Seize contracts, a six-decimal collateral token and constant mock prices. Each borrower deposits 10e6 collateral units and borrows 1e9 OHM units. Healthy scans use unexpired positions; eligible batches use expired positions. The Task holds the protocol seizer role and earns no keeper reward. Measurements use solc 0.8.36, optimizer 400, Prague and transaction isolation. `snapshotGasLastFrame` measures the `execute` call, excluding deployment and loan setup. Gas snapshots are stored in [BurnerLoansSeizerTaskGas.json](../../../../snapshots/BurnerLoansSeizerTaskGas.json).

| Borrowers checked or seized | Healthy scan, gas | All expired and seized, gas |
| --- | --- | --- |
| 1 | 200,480 | 564,283 |
| 25 | 1,213,329 | 2,167,380 |
| 50 | 2,271,480 | 4,097,897 |
| 51 | Not measured | 4,180,275 |
| 100 | 4,397,276 | 8,754,906 |
| 255 | Not measured | 29,941,834 |
| 500 | 21,859,263 | Not representable by the uint8 seizure limit |
| 1000 | 44,825,810 | Not representable by the uint8 seizure limit |

These are workload examples, not universal safe limits. Duplicate detection in Seize is quadratic, so larger eligible batches do not scale linearly. Vault-backed collateral, price routes, payout behavior and borrower state can change costs. The body budget must also cover stale-cursor recovery; Heart needs gas for the outer reserve and subsequent tasks. Under this fixture, check=500 cannot finish a healthy page within a 10-million body budget; reducing check to 100 restores progress. Tune the scan and batch limits independently, leaving margin below the heartbeat's available gas, then rerun against the intended markets.

| ID | Caller | Workload | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SCAN-LIMITS-G01 | HEART_ROLE holder | Healthy scans of 1,25,50,100,500,1000 positions | Exact successful scan event and cursor; principal unchanged; gas measured separately from setup | Covered: [test][test_whenHealthyScanIsOne_thenMeasureGas], [test][test_whenHealthyScanIsTwentyFive_thenMeasureGas], [test][test_whenHealthyScanIsFifty_thenMeasureGas], [test][test_whenHealthyScanIsOneHundred_thenMeasureGas], [test][test_whenHealthyScanIsFiveHundred_thenMeasureGas], [test][test_whenHealthyScanIsOneThousand_thenMeasureGas] |
| BLSEIZ-SCAN-LIMITS-G02 | HEART_ROLE holder | Expired batches of 1,25,50,51,100,255 | All selected principal and collateral settled; no Task custody; gas measured separately from setup | Covered: [test][test_whenEligibleBatchIsOne_thenMeasureGas], [test][test_whenEligibleBatchIsTwentyFive_thenMeasureGas], [test][test_whenEligibleBatchIsFifty_thenMeasureGas], [test][test_whenEligibleBatchIsFiftyOne_thenMeasureGas], [test][test_whenEligibleBatchIsOneHundred_thenMeasureGas], [test][test_whenEligibleBatchIsMaxUint8_thenMeasureGas] |
| BLSEIZ-SCAN-LIMITS-G03 | HEART_ROLE holder | 500 healthy borrowers, 10-million body gas; change check500 to check100 | Oversized scan fails without progress; reduced page succeeds and saves cursor100 | Covered: [test][test_givenTenMillionGas_whenScanReduced_thenProgressResumes] |

[test_givenInactiveTask_whenLimitsSet_reverts]: ./setScanLimits.t.sol#L114
[test_givenPermittedCaller_whenLimitsSet]: ./setScanLimits.t.sol#L19
[test_givenTenMillionGas_whenScanReduced_thenProgressResumes]: ./integration/scanGas.t.sol#L74
[test_whenCallerHasNeitherRole_whenScanLimitsSet_reverts]: ./setScanLimits.t.sol#L61
[test_whenCheckLimitZero_reverts]: ./setScanLimits.t.sol#L78
[test_whenEligibleBatchIsFiftyOne_thenMeasureGas]: ./integration/scanGas.t.sol#L59
[test_whenEligibleBatchIsFifty_thenMeasureGas]: ./integration/scanGas.t.sol#L54
[test_whenEligibleBatchIsMaxUint8_thenMeasureGas]: ./integration/scanGas.t.sol#L69
[test_whenEligibleBatchIsOneHundred_thenMeasureGas]: ./integration/scanGas.t.sol#L64
[test_whenEligibleBatchIsOne_thenMeasureGas]: ./integration/scanGas.t.sol#L44
[test_whenEligibleBatchIsTwentyFive_thenMeasureGas]: ./integration/scanGas.t.sol#L49
[test_whenHealthyScanIsFifty_thenMeasureGas]: ./integration/scanGas.t.sol#L24
[test_whenHealthyScanIsFiveHundred_thenMeasureGas]: ./integration/scanGas.t.sol#L34
[test_whenHealthyScanIsOneHundred_thenMeasureGas]: ./integration/scanGas.t.sol#L29
[test_whenHealthyScanIsOneThousand_thenMeasureGas]: ./integration/scanGas.t.sol#L39
[test_whenHealthyScanIsOne_thenMeasureGas]: ./integration/scanGas.t.sol#L14
[test_whenHealthyScanIsTwentyFive_thenMeasureGas]: ./integration/scanGas.t.sol#L19
[test_whenInvalidBoundariesSeeded_reverts]: ./setScanLimits.t.sol#L97
[test_whenLimitsUnchanged_thenNoEvent]: ./setScanLimits.t.sol#L107
[test_whenRolesAndFullWidthBoundariesSeeded]: ./setScanLimits.t.sol#L42
[test_whenSeizureLimitExceedsCheckLimit_reverts]: ./setScanLimits.t.sol#L90
[test_whenSeizureLimitZero_reverts]: ./setScanLimits.t.sol#L84

# BurnerLoansYieldClaimerTask.setNextAssetIndex coverage plan

Source: [setNextAssetIndex](../../../policies/burnerloans/BurnerLoansYieldClaimerTask.sol#L325). Coverage is recorded in the Test column with passing focused tests and reciprocal scenario comments.

## Domains and notation

Scenario scope: `BLYC-CURSOR` identifies this contract/function.

Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each: independently fuzz a nonzero caller holding ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, or both. Guarantee both exclusive classes and overlap seeds, independently of inputs, lifecycle and dependency failures. Unauthorized fuzzing excludes every holder of either role. These roles have equivalent behavior in the rows using this family.

Own-policy admission: require Kernel-active BurnerLoansYieldClaimerTask; own inactivity uses `BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask)` before body/input/idempotent work. Preserve earlier local-state and authorization guards. Successful body scenarios assume Local active=true, except explicit admission failures.

ADMIN_ROLE or BURNER_LOANS_ADMIN_ROLE; inputuint256. Zeroreset special branch avoids registry getter. Nonzero requiresindex<CoreassetCount, then equality no-op.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Task interaction setup

Setter caller classes are ADMIN_ROLE without BURNER_LOANS_ADMIN_ROLE, BURNER_LOANS_ADMIN_ROLE without ADMIN_ROLE, and holders of both; seed each partition independently of inputs and lifecycle. Unauthorized callers hold neither role. Own Kernel activity is required before role/input validation; local disablement and Core lifecycle do not gate this setter. Only the selected field changes.

## Authorization

Own policy active; ROLES initialized. Rejected calls preserve state/events; admitted changed values emit only the named setter event.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-CURSOR-A01 | Fuzz caller holding neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE; exclude every holder of either | Any index, including zero and MAX256 | NotAuthorised | Covered: [test][test_whenUnauthorizedCallerSetsCursor_reverts] |
| BLYC-CURSOR-A02 | Fuzz ADMIN_ROLE holder without BURNER_LOANS_ADMIN_ROLE | Nonempty registered set; fuzz valid changed index0..count-1, seed0,last; task enabled, disabled or re-enabled | Store exact cursor and emit NextAssetIndexSet once; registry, gas settings and accounting unchanged | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_whenCursorResetToZero_storesExactInput], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-CURSOR-A03 | Fuzz BURNER_LOANS_ADMIN_ROLE holder without ADMIN_ROLE | Nonempty registered set; fuzz valid changed index0..count-1, seed0,last; task enabled, disabled or re-enabled | Store exact cursor and emit NextAssetIndexSet once; registry, gas settings and accounting unchanged | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_whenCursorResetToZero_storesExactInput], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |
| BLYC-CURSOR-A04 | Fuzz holder of both ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE | Nonempty registered set; fuzz valid changed index0..count-1, seed0,last; task enabled, disabled or re-enabled | Store exact cursor and emit NextAssetIndexSet once; registry, gas settings and accounting unchanged | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_whenCursorResetToZero_storesExactInput], [test][test_whenAuthorizedRoleAndLocalStateSeeds] |

## Successful execution

Fixed for this table: Accounting / events: Next beat starts selectedasset.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLYC-CURSOR-P01 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | index1..count−1, includingcount−1; current/different | Store exact accepted value; same no event | Covered: [test][test_whenChangedCursorIsValid_storesExactInput], [test][test_whenCurrentCursorProvided_isNoOp], [test][test_givenRegisteredAssets_whenCursorSelected_nextBeatStartsThere] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLYC-CURSOR-P02 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | index0, oldcursor0/nonzero; registrycount fails or0 | Zero accepted; noop if already0 | No count read; NextAssetIndexSet only when changed | Covered: [test][test_whenCursorResetToZero_storesExactInput], [test][test_whenRegistryCountReverts_zeroStillResetsCursor], [test][test_whenCurrentCursorProvided_isNoOp] |
| BLYC-CURSOR-P03 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | index=count, count+1,MAX256; existingcursor formerlyvalid after shrink | InvalidAssetIndex(index,count), including same out-of-range | No silent modulo in setter; task normalizes later | Covered: [test][test_whenCursorIsOutOfRange_reverts], [test][test_whenCursorBoundaryIsInvalid_reverts], [test][test_givenCursorInvalidAfterShrink_whenSameIndexSet_reverts] |

Co-located API assertions: `nextAssetIndex`. These must be asserted independently of the action return value.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLYC-CURSOR-P04 | Fuzz ADMIN_ROLE-only, BURNER_LOANS_ADMIN_ROLE-only and overlapping holders; seed each | false | Fuzz false/true independently | BurnerLoans_PolicyNotActive(BurnerLoansYieldClaimerTask) | Unchanged; no body/token/module calls or committed logs | Covered: [test][test_givenInactivePolicy_whenSetting_reverts] |

[test_givenCursorInvalidAfterShrink_whenSameIndexSet_reverts]: setNextAssetIndex.t.sol#L258
[test_givenInactivePolicy_whenSetting_reverts]: setNextAssetIndex.t.sol#L237
[test_givenRegisteredAssets_whenCursorSelected_nextBeatStartsThere]: setNextAssetIndex.t.sol#L213
[test_whenAuthorizedRoleAndLocalStateSeeds]: setNextAssetIndex.t.sol#L284
[test_whenChangedCursorIsValid_storesExactInput]: setNextAssetIndex.t.sol#L110
[test_whenCurrentCursorProvided_isNoOp]: setNextAssetIndex.t.sol#L183
[test_whenCursorBoundaryIsInvalid_reverts]: setNextAssetIndex.t.sol#L74
[test_whenCursorIsOutOfRange_reverts]: setNextAssetIndex.t.sol#L37
[test_whenCursorResetToZero_storesExactInput]: setNextAssetIndex.t.sol#L138
[test_whenRegistryCountReverts_zeroStillResetsCursor]: setNextAssetIndex.t.sol#L161
[test_whenUnauthorizedCallerSetsCursor_reverts]: setNextAssetIndex.t.sol#L17

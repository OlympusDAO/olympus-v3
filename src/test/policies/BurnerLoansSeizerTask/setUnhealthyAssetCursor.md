# BurnerLoansSeizerTask.setUnhealthyAssetCursor coverage plan

Source: [setUnhealthyAssetCursor](../../../policies/burnerloans/BurnerLoansSeizerTask.sol).
Scenario scope: `BLSEIZ-UNHEALTHY-CURSOR`.

The setter changes only unhealthy discovery progress. Its companion setter owns the other lane.
Own Kernel activity precedes ADMIN or burner_loans_admin authorization, managed-asset validation and
bounds checks. Recovery is available while paused and after re-enable/reactivation. Nonzero offsets
use the combined `getSeizableBorrowersBoundedFor(this,asset,index,0,0)` getter for bounds only;
zero never reads Lens. Validation precedes same-value equality. Lens price, custody and reward
reads are absent on this zero-sized query. MAX denotes the named numeric type's maximum.

No transfers, approvals or economic accounting writes occur. Static dependency failures roll back
all effects. Action/getter agreement and the unaffected lane are asserted directly. Two concrete
action test contracts inherit the shared cursor cases; each overrides only the lane it exercises.
The mixed-maturity stateful campaign also drains its backlog without resetting either final cursor.

| ID | Caller | Lifecycle | Input / pre-state | Expected result / effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-UNHEALTHY-CURSOR-A01 | Fuzz caller excluding every ADMIN or burner_loans_admin holder | Active; enabled | Arbitrary asset/index, including invalid inputs | NotAuthorised before membership/bounds; both cursors unchanged | Covered: [test][test_whenCallerHasNeitherRole_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-P01 | Fuzz ADMIN-only, BL-admin-only and overlap; each seeded | Active; enabled/disabled/re-enabled, each seeded | Population fuzz2..MAX256; index fuzz1..population-1; seeds1 andMAX256-1; other lane nonzero | Store only selected offset; exact AssetCursorSet with the shared Lens lane enum; other progress/lifecycle/settings unchanged | Covered: [test][test_givenPermittedCaller_whenNonzeroCursorSet], [test][test_whenRoleLifecycleAndNumericBoundariesSeeded] |
| BLSEIZ-UNHEALTHY-CURSOR-P02 | Same permitted caller partitions and seeds | Active; enabled/disabled/re-enabled | Both cursors1; select0; downstream reads revert | Selected cursor0, other cursor1; exact event; no downstream reads | Covered: [test][test_givenUnequalCursors_whenZeroSelected_thenBothResetWithoutLensReads], [test][test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads], [test][test_whenRoleLifecycleAndNumericBoundariesSeeded] |
| BLSEIZ-UNHEALTHY-CURSOR-I01 | ADMIN | Active; enabled | Unmanaged asset fuzz incl0/MAX160; index0/1/MAX256 seeds | AssetNotManaged(asset); no cursor created | Covered: [test][test_whenAssetUnmanaged_reverts], [test][test_whenUnmanagedAddressBoundariesSeeded_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-I02 | ADMIN | Active; enabled | Population fuzz0..MAX256; invalid nonzero index>=population; seed0/1,0/MAX256,1/1,3/3,MAX256/MAX256 | Exact Lens.InvalidStart(index,population), before equality; both cursors unchanged | Covered: [test][test_givenRealLoans_givenOutage_whenInvalidBorrowerCursorSelected_reverts], [test][test_whenCursorOutsidePopulation_reverts], [test][test_whenInvalidNumericBoundariesSeeded_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-P03 | ADMIN | Active; enabled | Current/proposed selected cursor1; valid population; other cursor0 | Validate bounds then event-free no-op; other lane unchanged | Covered: [test][test_whenCursorUnchanged_thenValidateAndNoEvent] |
| BLSEIZ-UNHEALTHY-CURSOR-I03 | ADMIN | Active; enabled | Selected cursor1 becomes stale when population shrinks to1; propose same1 | InvalidStart(1,1), preserving selected1 and other0 | Covered: [test][test_givenSavedCursorStale_whenSameValueSelected_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-I04 | ADMIN | Active; enabled | Nonzero offset; Lens bounds getter reverts | Exact dependency error; cursor, inventory and custody rollback | Covered: [test][test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved], [test][test_givenLensReadFailure_whenNonzeroCursorSelected_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-L01 | ADMIN | Inactive then reactivated; local enabled independently true/false | Managed asset; proposed0/1 | PolicyNotActive(Task) before body; successful independent update after reactivation | Covered: [test][test_givenInactiveTask_whenCursorSelected_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-P04 | ADMIN then HEART | Active; enabled | Real three-borrower market; select2 only in this lane, other0; then execute | Each scan starts at its own offset; healthy full suffix wraps; real principal unchanged | Covered: [test][test_whenBorrowerCursorSelected_thenExecutionResumesThere] |
| BLSEIZ-UNHEALTHY-CURSOR-P06 | ADMIN | Active; enabled | Other asset has selected cursor1 and pending turn; select A cursor2 | Only A selected cursor changes; B progress/turn and A accounting unchanged | Covered: [test][test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved] |
| BLSEIZ-UNHEALTHY-CURSOR-P05 | Authorized stateful handler | Arbitrary pause/re-enable history | Arbitrary independent valid lane recovery between bounded beats | Both cursor bounds, rotation, inventory and canonical custody remain consistent | Covered: [test][invariant_schedulerAndAccountingRemainConsistent] |
| BLSEIZ-UNHEALTHY-CURSOR-P07 | Fuzz all permitted role/state partitions; each seeded | Active; enabled/disabled/re-enabled | Selected current/proposed0; Lens bounds read reverts | Event-free no-op without downstream reads; both cursors remain0 | Covered: [test][test_whenRoleLifecycleAndNumericBoundariesSeeded], [test][test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads] |
| BLSEIZ-UNHEALTHY-CURSOR-L02 | Fuzz unauthorized caller incl0 | Inactive; enabled independently true/false | Broken ROLES; unmanaged asset0/indexMAX256 | PolicyNotActive(Task) before authorization and invalid inputs; both cursors unchanged | Covered: [test][test_givenInactiveTask_givenRolesBroken_whenUnauthorized_reverts] |
| BLSEIZ-UNHEALTHY-CURSOR-P08 | ADMIN | Active; enabled | Unequal cursors2/8; invoke the two named setters to select2 | First expiry setter is a no-op, unhealthy setter updates its own lane; exact unhealthy event; both end2 | Covered: [test][test_givenUnequalCursors_whenBothSettersRun_thenBothCursorsAreUpdated] |
| BLSEIZ-UNHEALTHY-CURSOR-P09 | ADMIN | Active; enabled | Unequal expiry2/unhealthy8; independently select this lane | Only selected lane changes; other nonzero retry offset remains | Covered: [test][test_givenUnequalCursors_whenOnlyUnhealthySelected_thenExpiryIsPreserved] |
| BLSEIZ-UNHEALTHY-CURSOR-P10 | ADMIN | Active; enabled | Unequal cursors; propose this lane's unchanged value | No event after bounds validation; other lane retains its own unequal value | Covered: [test][test_givenUnequalCursors_whenSelectedLaneUnchanged_thenEventFreeNoOp] |

[test_whenCallerHasNeitherRole_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L98
[test_givenPermittedCaller_whenNonzeroCursorSet]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L32
[test_whenRoleLifecycleAndNumericBoundariesSeeded]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L74
[test_givenUnequalCursors_whenZeroSelected_thenBothResetWithoutLensReads]: execute.t.sol#L1070
[test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L43
[test_whenAssetUnmanaged_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L114
[test_whenUnmanagedAddressBoundariesSeeded_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L120
[test_givenRealLoans_givenOutage_whenInvalidBorrowerCursorSelected_reverts]: integration/executeOracleOutage.t.sol#L1402
[test_whenCursorOutsidePopulation_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L127
[test_whenInvalidNumericBoundariesSeeded_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L133
[test_whenCursorUnchanged_thenValidateAndNoEvent]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L142
[test_givenSavedCursorStale_whenSameValueSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L153
[test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved]: integration/setUnhealthyAssetCursor.t.sol#L96
[test_givenLensReadFailure_whenNonzeroCursorSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L169
[test_givenInactiveTask_whenCursorSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L182
[test_whenBorrowerCursorSelected_thenExecutionResumesThere]: integration/setUnhealthyAssetCursor.t.sol#L27
[test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved]: integration/setUnhealthyAssetCursor.t.sol#L58
[invariant_schedulerAndAccountingRemainConsistent]: integration/progress.invariant.t.sol#L46
[test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L200
[test_givenInactiveTask_givenRolesBroken_whenUnauthorized_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L222
[test_givenUnequalCursors_whenBothSettersRun_thenBothCursorsAreUpdated]: execute.t.sol#L1045
[test_givenUnequalCursors_whenOnlyUnhealthySelected_thenExpiryIsPreserved]: execute.t.sol#L1272
[test_givenUnequalCursors_whenSelectedLaneUnchanged_thenEventFreeNoOp]: execute.t.sol#L1284

# BurnerLoansSeizerTask.setExpiredAssetCursor coverage plan

Source: [setExpiredAssetCursor](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L241).
Scenario scope: `BLSEIZ-EXPIRED-CURSOR`.

The setter changes only expired discovery progress. Its companion setter owns the other lane.
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
| BLSEIZ-EXPIRED-CURSOR-A01 | Fuzz caller excluding every ADMIN or burner_loans_admin holder | Active; enabled | Arbitrary asset/index, including invalid inputs | NotAuthorised before membership/bounds; both cursors unchanged | Covered: [test][test_whenCallerHasNeitherRole_reverts] |
| BLSEIZ-EXPIRED-CURSOR-P01 | Fuzz ADMIN-only, BL-admin-only and overlap; each seeded | Active; enabled/disabled/re-enabled, each seeded | Population fuzz2..MAX256; index fuzz1..population-1; seeds1 andMAX256-1; other lane nonzero | Store only selected offset; exact AssetCursorSet with the shared Lens lane enum; other progress/lifecycle/settings unchanged | Covered: [test][test_givenPermittedCaller_whenNonzeroCursorSet], [test][test_whenNonzeroCursorRoleLifecycleAndNumericBoundariesSeeded] |
| BLSEIZ-EXPIRED-CURSOR-P02 | Same permitted caller partitions and seeds | Active; enabled/disabled/re-enabled | Both cursors1; select0; downstream reads revert | Selected cursor0, other cursor1; exact event; no downstream reads | Covered: [test][test_givenUnequalCursors_whenZeroSelected_thenNoDownstreamReads], [test][test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads], [test][test_whenCursorResetRoleAndLifecycleBoundariesSeeded] |
| BLSEIZ-EXPIRED-CURSOR-I01 | ADMIN | Active; enabled | Unmanaged asset fuzz incl0/MAX160; index0/1/MAX256 seeds | AssetNotManaged(asset); no cursor created | Covered: [test][test_whenAssetUnmanaged_reverts], [test][test_whenUnmanagedAddressBoundariesSeeded_reverts] |
| BLSEIZ-EXPIRED-CURSOR-I02 | ADMIN | Active; enabled | Population fuzz0..MAX256; invalid nonzero index>=population; seed0/1,0/MAX256,1/1,3/3,MAX256/MAX256 | Exact Lens.InvalidStart(index,population), before equality; both cursors unchanged | Covered: [test][test_givenRealLoans_givenOutage_whenInvalidBorrowerCursorSelected_reverts], [test][test_whenCursorOutsidePopulation_reverts], [test][test_whenInvalidNumericBoundariesSeeded_reverts] |
| BLSEIZ-EXPIRED-CURSOR-P03 | ADMIN | Active; enabled | Current/proposed selected cursor1; valid population; other cursor0 | Validate bounds then event-free no-op; other lane unchanged | Covered: [test][test_whenCursorUnchanged_thenValidateAndNoEvent] |
| BLSEIZ-EXPIRED-CURSOR-I03 | ADMIN | Active; enabled | Selected cursor1 becomes stale when population shrinks to1; propose same1 | InvalidStart(1,1), preserving selected1 and other0 | Covered: [test][test_givenSavedCursorStale_whenSameValueSelected_reverts] |
| BLSEIZ-EXPIRED-CURSOR-I04 | ADMIN | Active; enabled | Nonzero offset; Lens bounds getter reverts | Exact dependency error; cursor, inventory and custody rollback | Covered: [test][test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved], [test][test_givenLensReadFailure_whenNonzeroCursorSelected_reverts] |
| BLSEIZ-EXPIRED-CURSOR-L01 | ADMIN | Inactive then reactivated; local enabled independently true/false | Managed asset; proposed0/1 | PolicyNotActive(Task) before body; successful independent update after reactivation | Covered: [test][test_givenInactiveTask_whenCursorSelected_reverts] |
| BLSEIZ-EXPIRED-CURSOR-P04 | ADMIN then HEART | Active; enabled | Real three-borrower market; select2 only in this lane, other0; then execute | Each scan starts at its own offset; healthy full suffix wraps; real principal unchanged | Covered: [test][test_whenBorrowerCursorSelected_thenExecutionResumesThere] |
| BLSEIZ-EXPIRED-CURSOR-P06 | ADMIN | Active; enabled | Other asset has selected cursor1 and pending turn; select A cursor2 | Only A selected cursor changes; B progress/turn and A accounting unchanged | Covered: [test][test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved] |
| BLSEIZ-EXPIRED-CURSOR-P05 | Authorized stateful handler | Arbitrary pause/re-enable history | Arbitrary independent valid lane recovery between bounded beats | Saved offsets stay within the original book; compaction may make them stale until next discovery; rotation, inventory and canonical custody remain consistent | Covered: [test][invariant_schedulerAndAccountingRemainConsistent] |
| BLSEIZ-EXPIRED-CURSOR-P07 | Fuzz all permitted role/state partitions; each seeded | Active; enabled/disabled/re-enabled | Selected current/proposed0; Lens bounds read reverts | Event-free no-op without downstream reads; both cursors remain0 | Covered: [test][test_whenZeroUnchangedRoleAndLifecycleBoundariesSeeded], [test][test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads] |
| BLSEIZ-EXPIRED-CURSOR-L02 | Fuzz unauthorized caller incl0 | Inactive; enabled independently true/false | Broken ROLES; unmanaged asset0/indexMAX256 | PolicyNotActive(Task) before authorization and invalid inputs; both cursors unchanged | Covered: [test][test_givenInactiveTask_givenRolesBroken_whenUnauthorized_reverts] |
| BLSEIZ-EXPIRED-CURSOR-P08 | ADMIN | Active; enabled | Unequal cursors2/8; invoke the two named setters to select2 | First expiry setter is a no-op, unhealthy setter updates its own lane; exact unhealthy event; both end2 | Covered: [test][test_givenUnequalCursors_whenBothSettersRun_thenBothCursorsAreUpdated] |
| BLSEIZ-EXPIRED-CURSOR-P09 | ADMIN | Active; enabled | Unequal expiry2/unhealthy8; independently select this lane | Only selected lane changes; other nonzero retry offset remains | Covered: [test][test_givenUnequalCursors_whenOnlyExpirySelected_thenUnhealthyIsPreserved] |
| BLSEIZ-EXPIRED-CURSOR-P10 | ADMIN | Active; enabled | Unequal cursors; propose this lane's unchanged value | No event after bounds validation; other lane retains its own unequal value | Covered: [test][test_givenUnequalCursors_whenSelectedLaneUnchanged_thenEventFreeNoOp] |

[test_whenCallerHasNeitherRole_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L155
[test_givenPermittedCaller_whenNonzeroCursorSet]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L32
[test_whenNonzeroCursorRoleLifecycleAndNumericBoundariesSeeded]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L74
[test_whenCursorResetRoleAndLifecycleBoundariesSeeded]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L88
[test_whenZeroUnchangedRoleAndLifecycleBoundariesSeeded]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L99
[test_givenUnequalCursors_whenZeroSelected_thenNoDownstreamReads]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L114
[test_givenPermittedCaller_whenCursorReset_thenNoDownstreamReads]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L43
[test_whenAssetUnmanaged_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L171
[test_whenUnmanagedAddressBoundariesSeeded_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L177
[test_givenRealLoans_givenOutage_whenInvalidBorrowerCursorSelected_reverts]: integration/executeOracleOutage.t.sol#L1973
[test_whenCursorOutsidePopulation_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L184
[test_whenInvalidNumericBoundariesSeeded_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L190
[test_whenCursorUnchanged_thenValidateAndNoEvent]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L199
[test_givenSavedCursorStale_whenSameValueSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L210
[test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved]: integration/setExpiredAssetCursor.t.sol#L96
[test_givenLensReadFailure_whenNonzeroCursorSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L226
[test_givenInactiveTask_whenCursorSelected_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L239
[test_whenBorrowerCursorSelected_thenExecutionResumesThere]: integration/setExpiredAssetCursor.t.sol#L27
[test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved]: integration/setExpiredAssetCursor.t.sol#L58
[invariant_schedulerAndAccountingRemainConsistent]: integration/progress.invariant.t.sol#L46
[test_givenPermittedCaller_whenZeroUnchanged_thenNoDownstreamReads]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L257
[test_givenInactiveTask_givenRolesBroken_whenUnauthorized_reverts]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L279
[test_givenUnequalCursors_whenBothSettersRun_thenBothCursorsAreUpdated]: setUnhealthyAssetCursor.t.sol#L13
[test_givenUnequalCursors_whenOnlyExpirySelected_thenUnhealthyIsPreserved]: setExpiredAssetCursor.t.sol#L9
[test_givenUnequalCursors_whenSelectedLaneUnchanged_thenEventFreeNoOp]: fixtures/BurnerLoansSeizerTaskCursorCases.t.sol#L132

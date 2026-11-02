# BurnerLoansSeizerTask.setNextAssetBorrowerIndex coverage plan

Source: [setNextAssetBorrowerIndex](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L222).

Scenario scope: `BLSEIZ-BORROWER-CURSOR`. ADMIN_ROLE alone, BURNER_LOANS_ADMIN_ROLE alone, or both may recover a managed asset's borrower cursor. Unauthorized fuzzing excludes all holders of either role. Own Kernel activity precedes authorization, membership and bounds validation. Enabled, disabled and re-enabled states permit recovery.

Require a managed asset even for reset0. Zero resets without Lens/Seize/Core reads. Validate nonzero offsets with a zero-count, zero-result Lens scan: Lens checks its canonical borrower count without reading positions, Risk or prices, and returns InvalidStart(index,population) for an invalid offset. This reuses the scan API without adding a direct Core/FLOAN dependency to the setter. Validate before same-value no-op; a previously valid but now stale nonzero offset must fail. Ordinary downstream read errors propagate without cursor changes.

Only the selected asset's borrower cursor changes. Asset traversal, other borrower cursors, membership, scan/gas settings, lifecycle, principal/collateral and balances remain unchanged. The next visit resumes from the chosen index. Manual cursor recovery is included in the existing fixed-registry accounting invariant.

| ID | Caller | Local active | Local enabled/history | Input or dependency condition | Expected result and effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-BORROWER-CURSOR-A01 | Fuzz caller with neither ADMIN_ROLE nor BURNER_LOANS_ADMIN_ROLE | true | Enabled | Arbitrary asset/index, including invalid combinations | NotAuthorised before membership/Lens reads | Covered: [test][test_whenCallerHasNeitherRole_whenBorrowerCursorSet_reverts] |
| BLSEIZ-BORROWER-CURSOR-P01 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | true | Enabled, disabled or re-enabled; seed each | Managed asset; population fuzz2..MAX256; index fuzz1..population-1; seed1,MAX256-1 | Exact AssetCursorSet(asset,index) and getter; zero-count Lens call; no Risk reads; other state unchanged | Covered: [test][test_givenPermittedCaller_whenNonzeroBorrowerCursorSet], [test][test_whenRoleLifecycleAndNumericBoundariesSeeded] |
| BLSEIZ-BORROWER-CURSOR-P02 | Fuzz ADMIN-only, BL-admin-only and overlap; seed each | true | Enabled, disabled or re-enabled; seed each | Managed asset; current cursor1; proposed0; downstream reads fail | Reset succeeds with exact event and no downstream calls | Covered: [test][test_givenPermittedCaller_whenBorrowerCursorReset_thenNoDownstreamReads], [test][test_whenRoleLifecycleAndNumericBoundariesSeeded] |
| BLSEIZ-BORROWER-CURSOR-I01 | ADMIN_ROLE | true | Enabled | Fuzz unmanaged asset, including zero; arbitrary index | AssetNotManaged(asset) before Lens; unchanged | Covered: [test][test_whenAssetUnmanaged_whenBorrowerCursorSet_reverts], [test][test_whenUnmanagedAssetBoundaries_whenBorrowerCursorSet_reverts] |
| BLSEIZ-BORROWER-CURSOR-I02 | ADMIN_ROLE | true | Enabled | Population fuzz0..MAX256; nonzero index fuzz max(1,population)..MAX256; seed population/index0/1,0/MAX256,1/1,3/3,MAX256/MAX256 | Lens.InvalidStart(index,population); unchanged | Covered: [test][test_whenBorrowerCursorOutsidePopulation_reverts], [test][test_whenInvalidBorrowerCursorBoundariesSeeded_reverts] |
| BLSEIZ-BORROWER-CURSOR-P03 | ADMIN_ROLE | true | Enabled | Current/proposed cursor1; valid population | Validate then event-free no-op | Covered: [test][test_whenBorrowerCursorUnchanged_thenValidateAndNoEvent] |
| BLSEIZ-BORROWER-CURSOR-I03 | ADMIN_ROLE | true | Enabled | Current/proposed cursor1; population shrinks to1 | InvalidStart(1,1) before equality shortcut; retain old cursor until explicit reset | Covered: [test][test_givenSavedCursorStale_whenSameBorrowerCursorSet_reverts] |
| BLSEIZ-BORROWER-CURSOR-I04 | ADMIN_ROLE | true | Enabled | Nonzero cursor; Lens validation reverts | Exact dependency error; unchanged | Covered: [test][test_givenLensReadFails_whenNonzeroBorrowerCursorSet_reverts], [accounting][test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved] |
| BLSEIZ-BORROWER-CURSOR-L01 | ADMIN_ROLE | false then restored | Enabled/disabled independently | Managed asset; valid index, including0 | Own PolicyNotActive before body/no-op; successful retry after activation | Covered: [test][test_givenInactiveTask_whenBorrowerCursorSet_reverts] |
| BLSEIZ-BORROWER-CURSOR-P04 | ADMIN_ROLE then HEART_ROLE | true | Enabled | Set cursor2 in a real three-borrower market, then execute | Lens starts at2; healthy suffix wraps; principal/collateral unchanged | Covered: [test][test_whenBorrowerCursorSelected_thenExecutionResumesThere] |
| BLSEIZ-BORROWER-CURSOR-P06 | ADMIN_ROLE | true | Enabled | B already has borrower cursor1 and is the next asset; set A cursor2 | A changes to2; B cursor1, pending B visit and real A principal remain unchanged | Covered: [test][test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved] |
| BLSEIZ-BORROWER-CURSOR-P05 | Authorized handler | true | Arbitrary pause/re-enable history | Arbitrary valid borrower cursor recovery between beats | Borrower bounds, asset rotation and authoritative accounting remain consistent | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent] |

- [x] Write named tests, then implement the recovery setter.
- [x] Run focused tests, invariant, formatting/lint and reciprocal mapping checks.

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenInactiveTask_whenBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L208
[test_givenLensReadFails_whenNonzeroBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L195
[test_givenOtherAssetHasProgress_whenBorrowerCursorSet_thenOtherProgressIsPreserved]: ./integration/setNextAssetBorrowerIndex.t.sol#L41
[test_givenPermittedCaller_whenBorrowerCursorReset_thenNoDownstreamReads]: ./setNextAssetBorrowerIndex.t.sol#L41
[test_givenPermittedCaller_whenNonzeroBorrowerCursorSet]: ./setNextAssetBorrowerIndex.t.sol#L30
[test_givenSavedCursorStale_whenSameBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L174
[test_whenAssetUnmanaged_whenBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L123
[test_whenBorrowerCursorOutsidePopulation_reverts]: ./setNextAssetBorrowerIndex.t.sol#L147
[test_whenBorrowerCursorSelected_thenExecutionResumesThere]: ./integration/setNextAssetBorrowerIndex.t.sol#L27
[test_whenBorrowerCursorUnchanged_thenValidateAndNoEvent]: ./setNextAssetBorrowerIndex.t.sol#L164
[test_whenCallerHasNeitherRole_whenBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L101
[test_whenInvalidBorrowerCursorBoundariesSeeded_reverts]: ./setNextAssetBorrowerIndex.t.sol#L155
[test_whenRoleLifecycleAndNumericBoundariesSeeded]: ./setNextAssetBorrowerIndex.t.sol#L74
[test_whenUnmanagedAssetBoundaries_whenBorrowerCursorSet_reverts]: ./setNextAssetBorrowerIndex.t.sol#L136

[test_givenLoans_whenCursorValidationFails_thenAccountingIsPreserved]: ./integration/setNextAssetBorrowerIndex.t.sol#L65

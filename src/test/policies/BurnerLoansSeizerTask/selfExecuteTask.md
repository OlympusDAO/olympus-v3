# BurnerLoansSeizerTask.selfExecuteTask coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [selfExecuteTask](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L276). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-SELF-EXECUTE` identifies this contract/function.

Only self; external ADMIN/HEART/SEIZER roles do not bypass. Test via execute for production call path; direct self-prank only to isolate algorithm.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

SeizerTask management requires its own Kernel activity and remains available while paused. Add/removeAsset is ADMIN-only; scan/gas/cursor updates accept ADMIN or BL admin. Added assets must be registered in Core. Execute checks own Kernel activity, authenticates HEART, then returns if disabled. Self execution is self-only and requires own Kernel activity. Each invocation processes one asset. Lens and Seize are immutable bindings.

Core has no Lens pointer. The task uses Lens.getSeizableBorrowersBoundedFor with independent checked/result bounds. A zero-candidate scan commits its returned cursor. Successful settlement rewinds the returned index by the number of selected borrowers, floored at zero, accounting conservatively for active-list compaction; end-of-page zero stays zero. Before scanning a nonzero cursor, the task reads Lens.getActiveBorrowerCount and resets an out-of-range offset to zero within the same visit. Other scan/seizure failures preserve the applicable borrower progress. Asset traversal advances before external work; outer execute restores rotation if the entire self-call fails. A 50,000-gas outer reserve protects cleanup and later Heart tasks. Seizure remains one atomic batch: gas exhaustion never commits only part of the selected borrowers.

## Borrower cursor and list compaction

The cursor indexes one asset's active-borrower list. A healthy scan of indices 0..2 in a list of four saves start=3. Before the next A visit, two borrowers repay or an independent keeper seizes them. FLOAN removes entries with swap-and-pop: the list now has length 2, so start=3 is invalid. The task reads the current count before scanning, resets start to zero, and makes one valid scan during the same A visit, settling remaining eligible debt immediately. B still gets its next turn and B's borrower cursor is unchanged. An empty list is repaired the same way.

Keep the per-asset cursor: finding the first X eligible borrowers still requires inspecting borrowers. Restarting every bounded scan at zero can repeatedly scan a healthy prefix as large as maxBorrowersToCheck, permanently hiding an eligible suffix. Retaining the cursor makes that suffix reachable. After its own successful batch the Task rewinds by the selected borrower count to accommodate compaction. External compaction gets the single same-visit repair above; it does not require a reset-only heartbeat. The configured gas budget covers one bounded count read for a nonzero cursor and one scan; no rejected-offset scan is needed.

| ID | Caller | Between-visit changes | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-P11 | Self through execute | Real healthy scan saves 3 of 4; two borrowers repay, leaving 2; remaining debt matures | Retry zero and settle one in the same A visit | One principal remains; B gets next turn; B cursor unchanged | Covered: [test][test_givenBorrowersRepaidBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt] |
| BLSEIZ-SELF-EXECUTE-P12 | Self through execute | Real healthy scan saves 3 of 4; independent keeper seizes two between visits | Retry zero and settle one in the same A visit | Foreign and Task defaults reconcile principal; rotation preserved | Covered: [test][test_givenThirdPartySeizesBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt] |
| BLSEIZ-SELF-EXECUTE-P13 | Self through execute | Healthy borrower at index 0; expired borrower at index 1; check=seize=1 | First A visit saves 1; second A visit settles expired borrower | Healthy prefix cannot hide eligible suffix permanently | Covered: [test][test_givenHealthyPrefix_whenBoundedScansRepeat_thenEligibleSuffixRemainsReachable] |
| BLSEIZ-SELF-EXECUTE-L01 | Self | Task Kernel-inactive; enabled/disabled independently | BurnerLoans_PolicyNotActive(Task) | No task progress | Covered: [test][test_givenTaskInactive_whenSelfCalls_reverts] |

## Numeric boundaries and arithmetic

Fixed for this table: Accounting / events: Core assets and managed assets distinct; asset iterator survives shrink.

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-N01 | Self | Nassets0,1,multiple; nextIndex0,last,out-of-range/MAX256 | Empty no-op; normalize modulo, advance one asset | Unmapped |

## Authorization

Any caller except this contract is rejected before lifecycle, registry or gas-dependent work. Fuzz callers including EOAs, ADMIN/HEART role holders and sibling policies, excluding only self.

| ID | Caller | Inputs / competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-A01 | Fuzz external caller excluding self | Active/enabled task | OnlySelf | No effects | Covered: [test][test_whenCallerIsNotSelf_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-P01 | Self | SEIZER role missing vs present | Missing emits SeizerRoleMissing; no scan | Asset iterator advanced; borrower cursor preserved | Unmapped |
| BLSEIZ-SELF-EXECUTE-P02 | Self through execute | Two fixed assets; finite eligible backlog; active-list swaps after defaults | A settles 25 of 50; B gets a turn; A settles remaining 25 next visit | No reset-only visit or permanent starvation; accounting matches across arbitrary pause/gas/batch settings | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent], [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-P03 | Self through execute | Independent scan and seizure bounds; successful 25-borrower settlement | Store max(scannedNextIndex-selectedCount,0); scan never discards candidates beyond a full batch | SeizureExecuted agrees with stored cursor; authoritative debt/collateral reconcile; task holds no reward | Covered: [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles] |
| BLSEIZ-SELF-EXECUTE-P04 | Self through execute | Lens raises injected ScanReadFailed(); current borrower cursor is valid | ScanFailed(asset, first4bytes); no seizure | Asset iterator advances; borrower progress unchanged | Covered: [test][test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn] |
| BLSEIZ-SELF-EXECUTE-P05 | Self through execute | Saved start=3; current active borrower count=1 | Read the live count, reset the stale cursor to zero, and issue exactly one valid scan; never attempt start=3 | Remaining expired debt settles without consuming a reset-only turn; rotate to next asset | Covered: [test][test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn] |
| BLSEIZ-SELF-EXECUTE-P06 | Self through execute | Empty active list with saved start=1 | Read count=0 and scan once from zero within this visit | Cursor resets to zero; no pricing reads or seizure; rotate normally | Covered: [test][test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn] |
| BLSEIZ-SELF-EXECUTE-P07 | Self through execute | Lens selects a batch; Seize raises SettlementFailed() | SeizureFailed(asset,selector) | Rotate assets; preserve cursor/debt; later A visit retries successfully | Covered: [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |
| BLSEIZ-SELF-EXECUTE-P08 | Self through execute | Lens consumes forwarded gas and reverts without error bytes; bounded task retains enough gas for the catch | ScanFailed(asset,0x00000000) | Asset iterator advances; borrower cursor preserved; no partial positions; later Heart task still executes | Unmapped |
| BLSEIZ-SELF-EXECUTE-P09 | Self through execute | Check limit 4, seizure limit 1; first two borrowers healthy, third eligible | Scan beyond the seizure count; forward third borrower only; fourth index unread | No eligible candidate discarded by truncation | Covered: [test][test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded] |
| BLSEIZ-SELF-EXECUTE-P10 | Self through execute | Task entry's registration report was previously true; current Core market lookup rejects it | ScanFailed(asset,AssetNotConfigured.selector) | No borrower progress; rotate; following registered asset remains reachable | Covered: [test][test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated] |
| BLSEIZ-SELF-EXECUTE-P14 | Self through execute | Nonzero saved cursor; Lens borrower-count read fails | ScanFailed(asset,selector); no scan or seizure | Preserve borrower cursor; asset iterator advances | Covered: [test][test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate] |

Co-located API assertions: `assetCursor`, `nextAssetIndex`. These must be asserted independently of the action return value.

- [ ] Review these expectations.
- [ ] Implement named Foundry tests and boundary seed drivers.
- [ ] Map each row to passing tests.

## Test organization

[selfExecuteTask.t.sol](./selfExecuteTask.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenBorrowersRepaidBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L119
[test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn]: ./integration/execute.t.sol#L287
[test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles]: ./integration/execute.t.sol#L33
[test_givenHealthyPrefix_whenBoundedScansRepeat_thenEligibleSuffixRemainsReachable]: ./integration/execute.t.sol#L178
[test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn]: ./execute.t.sol#L66
[test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry]: ./integration/execute.t.sol#L203
[test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded]: ./integration/execute.t.sol#L65
[test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn]: ./integration/execute.t.sol#L95
[test_givenTaskInactive_whenSelfCalls_reverts]: ./selfExecuteTask.t.sol#L22
[test_givenThirdPartySeizesBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L145
[test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated]: ./integration/execute.t.sol#L229
[test_whenCallerIsNotSelf_reverts]: ./selfExecuteTask.t.sol#L13

[test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate]: ./execute.t.sol#L199

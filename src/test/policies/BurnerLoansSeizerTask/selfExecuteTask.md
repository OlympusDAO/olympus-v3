# BurnerLoansSeizerTask.selfExecuteTask coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [selfExecuteTask](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L276). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-SELF-EXECUTE` identifies this contract/function.

Only self; external ADMIN/HEART/SEIZER roles do not bypass. Test via execute for production call path; direct self-prank only to isolate algorithm.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

SeizerTask management requires its own Kernel activity and remains available while paused. Add/removeAsset is ADMIN-only; scan/gas/cursor updates accept ADMIN or BL admin. Added assets must be registered in Core. Execute checks own Kernel activity, authenticates HEART, then returns if disabled. Self execution is self-only and requires own Kernel activity. Each invocation processes one asset. Lens and Seize are immutable bindings.

Core has no Lens pointer. The task first uses Lens.getExpiredBorrowersBoundedFor; only an expiry-empty page permits Lens.getSeizableBorrowersBoundedFor from the same start and caps. A zero-candidate scan commits its returned cursor. Successful settlement rewinds the returned index by the number of selected borrowers, floored at zero, accounting conservatively for active-list compaction; end-of-page zero stays zero. Before scanning a nonzero cursor, the task reads Lens.getActiveBorrowerCount and resets an out-of-range offset to zero within the same visit. Expiry/count failures and rejected settlement retain the applicable retry cursor; priced discovery failures advance to the proven-empty expiry cursor. Asset traversal advances before external work; outer execute restores rotation if the entire self-call fails. A 50,000-gas outer reserve protects cleanup and later Heart tasks. Seizure remains one atomic batch: gas exhaustion never commits only part of the selected borrowers.

## Borrower cursor and list compaction

Expiry discovery runs first. A nonempty selection is the only settlement batch attempted that visit,
and no priced discovery runs before or after it. An expiry failure emits ScanFailed and retains the
cursor. Only an expiry-empty page permits priced discovery from the same start; its failure reports
the exact error and advances to the proven-empty expiry cursor without health classification.
Successful settlement retains compaction rewind; rejected settlement preserves retry progress.
The expiry quote retains custody and Risk reward-service admission. See [execute scenarios](./execute.md).

The gas budget covers at most two scans per asset visit, plus the existing optional count read.

The cursor indexes one asset's active-borrower list. A healthy scan of indices 0..2 in a list of four saves start=3. Before the next A visit, two borrowers repay or an independent keeper seizes them. FLOAN removes entries with swap-and-pop: the list now has length 2, so start=3 is invalid. The task reads the current count before scanning, resets start to zero, and makes one expiry scan during the same A visit, settling remaining eligible debt immediately. B still gets its next turn and B's borrower cursor is unchanged. An empty list is repaired the same way.

Keep the per-asset cursor: finding the first X eligible borrowers still requires inspecting borrowers. Restarting every bounded scan at zero can repeatedly scan a healthy prefix as large as maxBorrowersToCheck, permanently hiding an eligible suffix. Retaining the cursor makes that suffix reachable. After its own successful batch the Task rewinds by the selected borrower count to accommodate compaction. External compaction gets the single same-visit repair above; it does not require a reset-only heartbeat. The configured gas budget covers one bounded count read for a nonzero cursor and the bounded discovery attempts; no rejected-offset scan is needed.

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
| BLSEIZ-SELF-EXECUTE-N01 | Self | Reachable managed sets empty, single and multiple; valid pending index0/last after public setters and removals | Empty no-op; otherwise process pending asset and advance/wrap once | Covered: [test][test_givenEmptyRegistry_whenSelfCalls_thenNoWork], [test][test_givenSingleAsset_whenSelfCalls_thenCursorWraps], [test][test_givenTwoAssets_whenPendingIndexSelected], [test][test_givenAssetRemoved_whenSelfCalls_thenSurvivorIsVisited] |

## Authorization

Any caller except this contract is rejected before lifecycle, registry or gas-dependent work. Fuzz callers including EOAs, ADMIN/HEART role holders and sibling policies, excluding only self.

| ID | Caller | Inputs / competing fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-A01 | Fuzz external caller excluding self | Active/enabled task | OnlySelf | No effects | Covered: [test][test_whenCallerIsNotSelf_reverts] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-P01 | Self through execute | Task lacks SEIZER role, with every scan/settlement service failing if called | SeizerRoleMissing(asset), no discovery/settlement calls | Asset traversal advances; borrower cursor preserved; granting role restores progress | Covered: [test][test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates] |
| BLSEIZ-SELF-EXECUTE-P02 | Self through execute | Two fixed assets; finite eligible backlog; active-list swaps after defaults | A settles 25 of 50; B gets a turn; A settles remaining 25 next visit | No reset-only visit or permanent starvation; accounting matches across arbitrary pause/gas/batch settings | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent], [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles] |

## Scanning and progress

| ID | Caller | Cursor / gas / registry condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-P03 | Self through execute | Independent scan and seizure bounds; successful 25-borrower settlement | Store max(scannedNextIndex-selectedCount,0); scan never discards candidates beyond a full batch | SeizureExecuted agrees with stored cursor; authoritative debt/collateral reconcile; task holds no reward | Covered: [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles] |
| BLSEIZ-SELF-EXECUTE-P04 | Self through execute | Lens raises injected ScanReadFailed(); current borrower cursor is valid | ScanFailed(asset, first4bytes); no seizure | Asset iterator advances; borrower progress unchanged | Covered: [test][test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn] |
| BLSEIZ-SELF-EXECUTE-P05 | Self through execute | Saved start=3/count=1 or start=2/count=2; guarantee both | Read the live count, reset the stale cursor to zero, and issue expiry discovery from zero; never attempt start=3 or priced discovery for the resulting nonempty expiry selection | Remaining expired debt settles without consuming a reset-only turn; rotate to next asset | Covered: [test][test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn], [test][test_givenStaleCursor_givenOutage_whenExecuted] |
| BLSEIZ-SELF-EXECUTE-P06 | Self through execute | Empty active list with saved start=1 | Read count=0; run expiry and then priced discovery from zero within this visit | Cursor resets to zero; no pricing reads or seizure; rotate normally | Covered: [test][test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn] |
| BLSEIZ-SELF-EXECUTE-P07 | Self through execute | Lens selects a batch; Seize raises SettlementFailed() | SeizureFailed(asset,selector) | Rotate assets; preserve cursor/debt; later A visit retries successfully | Covered: [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |
| BLSEIZ-SELF-EXECUTE-P08 | Self through execute | Lens consumes forwarded gas and reverts without error bytes; bounded task retains enough gas for the catch | ScanFailed(asset,0x00000000) | Asset iterator advances; borrower cursor preserved; no partial positions; later Heart task still executes | Covered: [test][test_givenLensExhaustsGas_givenCatchGasSufficient_whenHeartRunsTasks] |
| BLSEIZ-SELF-EXECUTE-P09 | Self through execute | Check limit 4, seizure limit 1; first two borrowers healthy, third eligible | Scan beyond the seizure count; forward third borrower only; fourth index unread | No eligible candidate discarded by truncation | Covered: [test][test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded] |
| BLSEIZ-SELF-EXECUTE-P10 | Self through execute | Task entry's registration report was previously true; current Core market lookup rejects it | ScanFailed(asset,AssetNotConfigured.selector) | No borrower progress; rotate; following registered asset remains reachable | Covered: [test][test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated] |
| BLSEIZ-SELF-EXECUTE-P14 | Self through execute | Nonzero saved cursor; Lens borrower-count read fails | ScanFailed(asset,selector); no scan or seizure | Preserve borrower cursor; asset iterator advances | Covered: [test][test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate] |

Co-located API assertions: `assetCursor`, `nextAssetIndex`. These must be asserted independently of the action return value.

- [x] Review concrete branches and inherited guard order.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Test organization

[selfExecuteTask.t.sol](./selfExecuteTask.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.

## Local boundary and settlement arithmetic

Direct self-pranks isolate this external self-only function. Production execute checks local enablement before calling it; selfExecuteTask itself has no enabled-state check. Task does not custody ERC20 or calculate reward math; real Seize integration owns settlement deltas.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-L02 | Self | Kernel-active but locally disabled; asset with ready dependencies | Body still runs through self-only entry; direct external callers remain rejected | Covered: [test][test_givenDisabled_whenSelfCalls_thenBodyStillRuns] |
| BLSEIZ-SELF-EXECUTE-A02 | Fuzz every caller except self | Task inactive and cached ROLES broken | OnlySelf before activity/dependency checks; no progress | Covered: [test][test_givenInactive_givenRolesBroken_whenCallerIsNotSelf_reverts] |
| BLSEIZ-SELF-EXECUTE-N02 | Self via defensive harness only | Inject nextAssetIndex=MAX256; nonempty set | Normalize modulo without overflow and process one asset; this state is unreachable through public setters/removals | Covered: [test][test_givenMaximumDefensiveAssetIndex_whenSelfCalls_thenIndexNormalizes] |
| BLSEIZ-SELF-EXECUTE-P15 | Self through execute | Mock priced scan returns ordered [Alice,Bob], next6; expiry selection empty | Forward exact asset/borrowers once, store next-length, emit exact selected count/start/end | Covered: [test][test_whenScanReturnsBorrowers_thenForwardsExactBatchAndRewindsCursor] |
| BLSEIZ-SELF-EXECUTE-P16 | Self through execute | Successful nonempty batch, returned next equals selected count | Rewind to0 without underflow; exactly one batch; exact SeizureExecuted | Covered: [test][test_givenExpiryNextEqualsBatchLength_whenExecuted_thenCursorIsZero] |
| BLSEIZ-SELF-EXECUTE-P17 | Self through execute | Successful nonempty batch, returned next0 at population end | Keep cursor0; swap-and-pop membership/accounting reconcile | Covered: [test][test_givenExpiryBatchAtPopulationEnd_whenExecuted_thenCursorRemainsZero], [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles] |
| BLSEIZ-SELF-EXECUTE-P18 | Self through execute | Both discovery stages empty; priced next nonzero then0 on a later visit | Commit priced next, no Seize call, emit zero selected count; eventual wrap | Covered: [test][test_whenScanReturnsNoBorrowers_thenStoresCursorWithoutSettlement] |

## Discovery-stage control flow

Task holds SEIZER; active; gas sufficient unless stated. Both scanners use the same active-borrower window. A successful empty expiry scan is a maturity fact only, not a health classification.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-D01 | Self through execute | Expiry scan returns a nonempty batch; Seize succeeds | One expiry scan and one aggregate settlement; no priced scan before/after; compaction rewind | Covered: [test][test_givenExpiryCandidates_whenExecuted_thenOnlyExpiryBatchSettles] |
| BLSEIZ-SELF-EXECUTE-D02 | Self through execute | Expiry scan returns a nonempty batch; Seize reverts | SeizureFailed; repaired cursor retained; no priced scan; debt rollback | Covered: [test][test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists], [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |
| BLSEIZ-SELF-EXECUTE-D03 | Self through execute | Expiry scan reverts, even though a hypothetical priced scan could succeed | ScanFailed with exact expiry selector; no priced/settlement calls; cursor retained | Covered: [test][test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained] |
| BLSEIZ-SELF-EXECUTE-D04 | Self through execute | Expiry scan empty; priced scan reverts with pricing/config/lifecycle/custody quote error | ScanFailed with original selector; store expiry next, which may be nonzero or0 | Covered: [test][test_givenEmptyExpiryPage_givenPricedFailure_whenExecuted_thenProvenCursorIsStored] |
| BLSEIZ-SELF-EXECUTE-D05 | Self through execute | Valid nonzero saved cursor; authoritative count greater than start | Retain saved start and issue expiry scan from that exact input | Covered: [test][test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained] |
| BLSEIZ-SELF-EXECUTE-D06 | Self through execute | Count proves saved cursor stale; expiry quote or settlement fails inside catch | Persist repaired cursor0; retain debt; next asset gets turn | Covered: [test][test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists], [test][test_givenStaleCursor_givenServiceFailure_whenExecuted] |
| BLSEIZ-SELF-EXECUTE-D07 | Self through execute | Count proves saved cursor stale; whole body later fails/OOG | Repair and body events roll back; outer execute rotates assets and reports failure | Covered: [test][test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes] |
| BLSEIZ-SELF-EXECUTE-D08 | Self through execute | Saved cursor0; count getter would fail if called | Skip count read; discovery can still succeed from0 | Covered: [test][test_givenZeroCursor_givenCountReadBroken_whenExecuted_thenDiscoveryStillRuns] |

## Full-width forwarding boundary

The limits bound distinct list entries and selected results independently; the same values are forwarded to both stages. A small live population isolates numeric forwarding from practical gas costs.

| ID | Caller | Limits / population | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-N03 | Self through execute | check=MAX16, seize=MAX8; one unexpired borrower; expiry-empty page | Both Lens calls receive exact uint256-upcast limits and identical asset/start/Task actor; one priced health check; no truncation or additional cap | Covered: [test][test_givenMaximumLimits_whenExecuted_thenBothStagesReceiveFullWidthInputs], [test][test_givenMaximumLimits_givenOneUnexpiredBorrower_whenExecuted] |

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenBorrowersRepaidBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L143
[test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn]: ./integration/execute.t.sol#L311
[test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles]: ./integration/execute.t.sol#L34
[test_givenHealthyPrefix_whenBoundedScansRepeat_thenEligibleSuffixRemainsReachable]: ./integration/execute.t.sol#L202
[test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn]: ./execute.t.sol#L68
[test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry]: ./integration/execute.t.sol#L227
[test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded]: ./integration/execute.t.sol#L66
[test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn]: ./integration/execute.t.sol#L96
[test_givenTaskInactive_whenSelfCalls_reverts]: ./selfExecuteTask.t.sol#L23
[test_givenThirdPartySeizesBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L169
[test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated]: ./integration/execute.t.sol#L253
[test_whenCallerIsNotSelf_reverts]: ./selfExecuteTask.t.sol#L14
[test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate]: ./execute.t.sol#L278
[test_givenStaleCursor_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L178
[test_whenScanReturnsBorrowers_thenForwardsExactBatchAndRewindsCursor]: ./execute.t.sol#L302
[test_whenScanReturnsNoBorrowers_thenStoresCursorWithoutSettlement]: ./execute.t.sol#L323
[test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates]: ./execute.t.sol#L106
[test_givenDisabled_whenSelfCalls_thenBodyStillRuns]: ./selfExecuteTask.t.sol#L38
[test_givenEmptyExpiryPage_givenPricedFailure_whenExecuted_thenProvenCursorIsStored]: ./execute.t.sol#L486
[test_givenEmptyRegistry_whenSelfCalls_thenNoWork]: ./selfExecuteTask.t.sol#L70
[test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes]: ./execute.t.sol#L192
[test_givenExpiryBatchAtPopulationEnd_whenExecuted_thenCursorRemainsZero]: ./execute.t.sol#L699
[test_givenExpiryCandidates_whenExecuted_thenOnlyExpiryBatchSettles]: ./execute.t.sol#L398
[test_givenExpiryNextEqualsBatchLength_whenExecuted_thenCursorIsZero]: ./execute.t.sol#L416
[test_givenInactive_givenRolesBroken_whenCallerIsNotSelf_reverts]: ./selfExecuteTask.t.sol#L57
[test_givenMaximumLimits_givenOneUnexpiredBorrower_whenExecuted]: ./integration/executeOracleOutage.t.sol#L814
[test_givenMaximumLimits_whenExecuted_thenBothStagesReceiveFullWidthInputs]: ./execute.t.sol#L528
[test_givenSingleAsset_whenSelfCalls_thenCursorWraps]: ./selfExecuteTask.t.sol#L77
[test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists]: ./execute.t.sol#L430
[test_givenStaleCursor_givenServiceFailure_whenExecuted]: ./integration/executeOracleOutage.t.sol#L204
[test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained]: ./execute.t.sol#L459
[test_givenZeroCursor_givenCountReadBroken_whenExecuted_thenDiscoveryStillRuns]: ./execute.t.sol#L508
[test_givenAssetRemoved_whenSelfCalls_thenSurvivorIsVisited]: ./selfExecuteTask.t.sol#L109
[test_givenLensExhaustsGas_givenCatchGasSufficient_whenHeartRunsTasks]: ./execute.t.sol#L731
[test_givenMaximumDefensiveAssetIndex_whenSelfCalls_thenIndexNormalizes]: ./selfExecuteTask.t.sol#L131
[test_givenTwoAssets_whenPendingIndexSelected]: ./selfExecuteTask.t.sol#L85

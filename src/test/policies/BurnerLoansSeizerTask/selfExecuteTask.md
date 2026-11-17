# BurnerLoansSeizerTask.selfExecuteTask coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [selfExecuteTask](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L336). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-SELF-EXECUTE` identifies this contract/function.

Only self; external ADMIN/HEART/SEIZER roles do not bypass. Test via execute for production call path; direct self-prank only to isolate algorithm.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

SeizerTask management requires its own Kernel activity and remains available while paused. Add/removeAsset is ADMIN-only; scan/gas/cursor updates accept ADMIN or BL admin. Added assets must be registered in Core. Execute checks own Kernel activity, authenticates HEART, then returns if disabled. Self execution is self-only and requires own Kernel activity. Each invocation processes one asset. Lens and Seize are immutable bindings.

The task keeps independent `expiredAssetCursor` and `unhealthyAssetCursor` offsets per asset.
The preferred lane alternates separately per asset, starting with expiry. Empty discovery permits
the other lane to use its saved offset; a priced failure also permits expiry fallback. Expiry
discovery failure ends this visit. A nonempty selection consumes the visit, with at most one
successful settlement. Priced failures retain the unhealthy cursor. Both getters retain custody
and aggregate actor reward quoting.

## Borrower cursors and list compaction

If either offset is nonzero, one count read independently repairs stale offsets before discovery.
A count failure preserves both. A caught later failure retains repairs; whole-body failure rolls
back repairs and both cursors. The outer execute still rotates the asset using its50,000-gas reserve.
Seizure remains one atomic batch, so gas exhaustion never commits a partial default.

A successful settlement rewinds its own next offset by the selected count, floored at zero, with
end0 preserved. The other lane's saved offset remains unchanged until the next visit's existing
pre-scan repair. Repeated cross-lane rewinds must not erase traversal progress.
Swap-ins behind a valid cursor remain reachable after wrap for a finite backlog. A rejected selection
advances one saved offset with population wrap, with no second seizure attempt. Unhealthy execution-price refresh failures retain
retry progress. External compaction can move work behind a still-valid offset; subsequent wrap
keeps finite backlogs reachable, while out-of-range offsets are repaired in the same visit.

Each lane receives the configured check/result caps independently. A visit can inspect two different
bounded pages but make only one seizure attempt. A persistent settlement failure may require
governance to select a recovery cursor or narrow the result limit. Preferred lanes alternate per asset, including across whole-body failure.
Retaining both offsets avoids repeatedly scanning a healthy
prefix and preserves the unhealthy lane's pending work during oracle outages. The whole-body gas
budget still covers all count, scan and settlement work. See [execute scenarios](./execute.md).

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
| BLSEIZ-SELF-EXECUTE-P07 | Self through execute | Lens selects the sole borrower in a one-entry population; Seize raises SettlementFailed() | SeizureFailed(asset,selector) | Rotate assets; advance one wraps to0; preserve debt; later A visit retries successfully | Covered: [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |
| BLSEIZ-SELF-EXECUTE-P08 | Self through execute | Lens consumes forwarded gas and reverts without error bytes; bounded task retains enough gas for the catch | ScanFailed(asset,0x00000000) | Asset iterator advances; borrower cursor preserved; no partial positions; later Heart task still executes | Covered: [test][test_givenLensExhaustsGas_givenCatchGasSufficient_whenHeartRunsTasks] |
| BLSEIZ-SELF-EXECUTE-P09 | Self through execute | Check limit 4, seizure limit 1; first two borrowers healthy, third eligible | Scan beyond the seizure count; forward third borrower only; fourth index unread | No eligible candidate discarded by truncation | Covered: [test][test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded] |
| BLSEIZ-SELF-EXECUTE-P10 | Self through execute | Task entry's registration report was previously true; current Core market lookup rejects it | ScanFailed(asset,AssetNotConfigured.selector) | No borrower progress; rotate; following registered asset remains reachable | Covered: [test][test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated] |
| BLSEIZ-SELF-EXECUTE-P14 | Self through execute | Nonzero saved cursor; Lens borrower-count read fails | ScanFailed(asset,selector); no scan or seizure | Preserve borrower cursor; asset iterator advances | Covered: [test][test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate] |

Co-located API assertions: `expiredAssetCursor`, `nextAssetIndex`. These must be asserted independently of the action return value.

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
| BLSEIZ-SELF-EXECUTE-D02 | Self through execute | First visit; expiry scan selects the sole borrower in a one-entry population; Seize reverts | SeizureFailed; advance one wraps to0; no priced scan; debt rollback | Covered: [test][test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists], [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |
| BLSEIZ-SELF-EXECUTE-D03 | Self through execute | Expiry scan reverts, even though a hypothetical priced scan could succeed | ScanFailed with exact expiry selector; no priced/settlement calls; cursor retained | Covered: [test][test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained] |
| BLSEIZ-SELF-EXECUTE-D04 | Self through execute | Expiry scan empty; priced scan reverts with pricing/config/lifecycle/custody quote error | ScanFailed with original selector; store expiry next, which may be nonzero or0 | Covered: [test][test_givenEmptyExpiryPage_givenPricedFailure_whenExecuted_thenProvenCursorIsStored] |
| BLSEIZ-SELF-EXECUTE-D05 | Self through execute | Valid nonzero saved cursor; authoritative count greater than start | Retain saved start and issue expiry scan from that exact input | Covered: [test][test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained] |
| BLSEIZ-SELF-EXECUTE-D06 | Self through execute | Count proves saved cursor stale; expiry quote or settlement fails inside catch | Scan failure retains repair0; singleton rejection advances one with wrap; retain debt; next asset gets turn | Covered: [test][test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists], [test][test_givenStaleCursor_givenServiceFailure_whenExecuted] |
| BLSEIZ-SELF-EXECUTE-D07 | Self through execute | Count proves saved cursor stale; whole body later fails/OOG | Repair and body events roll back; outer execute rotates assets and reports failure | Covered: [test][test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes] |
| BLSEIZ-SELF-EXECUTE-D08 | Self through execute | Saved cursor0; count getter would fail if called | Skip count read; discovery can still succeed from0 | Covered: [test][test_givenZeroCursor_givenCountReadBroken_whenExecuted_thenDiscoveryStillRuns] |
| BLSEIZ-SELF-EXECUTE-D09 | Self through execute | Independent expiry2/unhealthy8; both scans empty | Each scan uses its own saved start and commits its own next offset | Covered: [test][test_givenIndependentCursors_whenPagesEmpty_thenEachLaneAdvancesItsOwnPage] |
| BLSEIZ-SELF-EXECUTE-D10 | Self through execute | Expiry2/unhealthy8; expiry succeeds, unhealthy fails | Expiry advances4; unhealthy retains8 | Covered: [test][test_givenIndependentCursors_whenUnhealthyScanFails_thenItsRetryOffsetIsRetained] |
| BLSEIZ-SELF-EXECUTE-D11 | Self through execute | Expired batch succeeds; other cursor equal to or later than scan start; include end0 | Rewind executing lane by selected count; retain the other lane while its offset is valid | Covered: [test][test_givenExpiredBatch_givenValidUnhealthyCursor_whenExecuted], [test][test_givenExpiredEndBatch_givenValidUnhealthyCursor_whenExecuted], [test][test_givenEqualCursors_whenExpiryBatchCompacts_thenOtherLaneRevisitsStart] |
| BLSEIZ-SELF-EXECUTE-D12 | Self through execute | Unhealthy batch succeeds; expiry offset earlier/later than priced scan start | Preserve valid expiry progress regardless of its ordering relative to this scan | Covered: [test][test_givenUnhealthyBatch_whenExpiryCursorIsEarlier_thenItIsPreserved], [test][test_givenUnhealthyBatch_givenValidExpiredCursor_whenExecuted] |
| BLSEIZ-SELF-EXECUTE-D13 | Self through execute | One cursor is stale before discovery or becomes stale after the other lane settles | Settlement preserves other offset; next visit resets only stale offsets before scanning; retain valid lane progress | Covered: [test][test_givenOnlyUnhealthyCursorStale_whenExecuted_thenExpiryOffsetIsPreserved], [test][test_givenOnlyExpiryCursorStale_whenExecuted_thenUnhealthyOffsetIsPreserved], [test][test_givenExpiredBatch_givenOtherCursorBecomesStale_whenExecuted] |
| BLSEIZ-SELF-EXECUTE-D14 | Self through execute | Expiry or unhealthy batch completes; empty unhealthy pages included | SeizureExecuted identifies its shared Lens Selection lane and that lane's exact start/next offsets and batch length | Covered: [test][test_givenExpiredBatch_whenExecuted_thenEventIdentifiesItsLane], [test][test_givenUnhealthyBatch_whenExecuted_thenEventIdentifiesItsLane] |
| BLSEIZ-SELF-EXECUTE-P19 | Self through execute | Randomized mixed-maturity history and independent cursor changes | Bounded final drain preserves cursor/order and settles every expired and future-maturity unhealthy borrower before maturity; authoritative accounting clears | Covered: [test][invariant_mixedBacklogRemainsReachable] |

## Full-width forwarding boundary

The limits bound inspected entries per lane and selected results independently; the same caps are forwarded to both lanes. A small live population isolates numeric forwarding from practical gas costs.

| ID | Caller | Limits / population | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-SELF-EXECUTE-N03 | Self through execute | check=MAX16, seize=MAX8; one unexpired borrower; expiry-empty page | Both Lens calls receive exact uint256-upcast limits and identical asset/Task actor and each lane's own start; one priced health check; no truncation or additional cap | Covered: [test][test_givenMaximumLimits_whenExecuted_thenBothStagesReceiveFullWidthInputs], [test][test_givenMaximumLimits_givenOneUnexpiredBorrower_whenExecuted] |

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenBorrowersRepaidBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L158
[test_givenEmptyMarketWithStaleCursor_whenVisited_thenRecoveryCompletesSameTurn]: ./integration/execute.t.sol#L364
[test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles]: ./integration/execute.t.sol#L34
[test_givenHealthyPrefix_whenBoundedScansRepeat_thenEligibleSuffixRemainsReachable]: ./integration/execute.t.sol#L232
[test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn]: ./execute.t.sol#L87
[test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry]: ./integration/execute.t.sol#L266
[test_givenSparseCandidates_whenScanLimitExceedsBatchLimit_thenNoCandidateIsDiscarded]: ./integration/execute.t.sol#L75
[test_givenStaleCursor_whenAssetVisited_thenRecoveryAndSettlementShareOneTurn]: ./integration/execute.t.sol#L105
[test_givenTaskInactive_whenSelfCalls_reverts]: ./selfExecuteTask.t.sol#L23
[test_givenThirdPartySeizesBetweenVisits_whenCursorIsStale_thenSameVisitSeizesRemainingDebt]: ./integration/execute.t.sol#L194
[test_givenUnsupportedEntry_whenExecuted_thenScanFailureIsIsolated]: ./integration/execute.t.sol#L297
[test_whenCallerIsNotSelf_reverts]: ./selfExecuteTask.t.sol#L14
[test_givenBorrowerCountReadReverts_whenExecuted_thenCursorPreservedAndAssetsRotate]: ./execute.t.sol#L325
[test_givenStaleCursor_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L723
[test_whenScanReturnsBorrowers_thenForwardsExactBatchAndRewindsCursor]: ./execute.t.sol#L358
[test_whenScanReturnsNoBorrowers_thenStoresCursorWithoutSettlement]: ./execute.t.sol#L385
[test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates]: ./execute.t.sol#L143
[test_givenDisabled_whenSelfCalls_thenBodyStillRuns]: ./selfExecuteTask.t.sol#L38
[test_givenEmptyExpiryPage_givenPricedFailure_whenExecuted_thenProvenCursorIsStored]: ./execute.t.sol#L604
[test_givenEmptyRegistry_whenSelfCalls_thenNoWork]: ./selfExecuteTask.t.sol#L70
[test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes]: ./execute.t.sol#L234
[test_givenExpiryBatchAtPopulationEnd_whenExecuted_thenCursorRemainsZero]: ./execute.t.sol#L857
[test_givenExpiryCandidates_whenExecuted_thenOnlyExpiryBatchSettles]: ./execute.t.sol#L476
[test_givenExpiryNextEqualsBatchLength_whenExecuted_thenCursorIsZero]: ./execute.t.sol#L509
[test_givenInactive_givenRolesBroken_whenCallerIsNotSelf_reverts]: ./selfExecuteTask.t.sol#L57
[test_givenMaximumLimits_givenOneUnexpiredBorrower_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1476
[test_givenMaximumLimits_whenExecuted_thenBothStagesReceiveFullWidthInputs]: ./execute.t.sol#L651
[test_givenSingleAsset_whenSelfCalls_thenCursorWraps]: ./selfExecuteTask.t.sol#L77
[test_givenStaleCursor_givenExpirySettlementFails_whenExecuted_thenRepairPersists]: ./execute.t.sol#L538
[test_givenStaleCursor_givenServiceFailure_whenExecuted]: ./integration/executeOracleOutage.t.sol#L763
[test_givenValidCursor_givenExpiryScanFails_whenExecuted_thenCursorIsRetained]: ./execute.t.sol#L572
[test_givenZeroCursor_givenCountReadBroken_whenExecuted_thenDiscoveryStillRuns]: ./execute.t.sol#L631
[test_givenAssetRemoved_whenSelfCalls_thenSurvivorIsVisited]: ./selfExecuteTask.t.sol#L109
[test_givenLensExhaustsGas_givenCatchGasSufficient_whenHeartRunsTasks]: ./execute.t.sol#L1571
[test_givenMaximumDefensiveAssetIndex_whenSelfCalls_thenIndexNormalizes]: ./selfExecuteTask.t.sol#L140
[test_givenTwoAssets_whenPendingIndexSelected]: ./selfExecuteTask.t.sol#L85

[test_givenIndependentCursors_whenPagesEmpty_thenEachLaneAdvancesItsOwnPage]: execute.t.sol#L886
[test_givenIndependentCursors_whenUnhealthyScanFails_thenItsRetryOffsetIsRetained]: execute.t.sol#L910
[test_givenExpiredBatch_givenValidUnhealthyCursor_whenExecuted]: execute.t.sol#L934
[test_givenExpiredEndBatch_givenValidUnhealthyCursor_whenExecuted]: execute.t.sol#L952
[test_givenEqualCursors_whenExpiryBatchCompacts_thenOtherLaneRevisitsStart]: execute.t.sol#L1169
[test_givenUnhealthyBatch_whenExpiryCursorIsEarlier_thenItIsPreserved]: execute.t.sol#L974
[test_givenUnhealthyBatch_givenValidExpiredCursor_whenExecuted]: execute.t.sol#L996
[test_givenOnlyUnhealthyCursorStale_whenExecuted_thenExpiryOffsetIsPreserved]: execute.t.sol#L1029
[test_givenOnlyExpiryCursorStale_whenExecuted_thenUnhealthyOffsetIsPreserved]: execute.t.sol#L1128

[test_givenExpiredBatch_whenExecuted_thenEventIdentifiesItsLane]: ./execute.t.sol#L1188
[test_givenUnhealthyBatch_whenExecuted_thenEventIdentifiesItsLane]: ./execute.t.sol#L1201

[invariant_mixedBacklogRemainsReachable]: integration/progressMixedMaturity.invariant.t.sol#L50
[test_givenExpiredBatch_givenOtherCursorBecomesStale_whenExecuted]: ./execute.t.sol#L1527

# BurnerLoansSeizerTask.execute coverage plan

Implemented scan binding: read the constructor-bound Lens directly. Core owns no Lens pointer. Lens has no local enabled state or Kernel membership prerequisite; Seize is the direct operational Policy dependency. Core is derived from Seize and must match Lens.

Source: [execute](../../../policies/burnerloans/BurnerLoansSeizerTask.sol#L291). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLSEIZ-EXECUTE` identifies this contract/function.

Execute requires own Kernel activity, authenticates HEART, then returns if disabled. Kernel-inactive execution reverts even when disabled. Own inactivity rejects before any cached ROLES lookup.

HEART role caller; configured gas isolation. Task must be Kernel-active; local enablement is independent. Core/Seize own state checked by actual Lens/action route.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Function context

Management requires own Kernel activity, permits local pause, and admits only Core-registered assets. Add/removeAsset remains ADMIN-only; scan/gas limits accept ADMIN or BL admin. Execute checks own Kernel activity before HEART authorization and its disabled no-op. One asset is attempted per invocation using immutable Lens/Seize bindings.

The task reserves 50,000 outer gas for cleanup and forwards at most executionGasLimit to its self-call. Whole-body failure reports at most four return-data bytes and commits asset rotation outside the reverted call. Successful bodies already rotated before scanning. Exactly one asset turn is consumed either way; disabled execution consumes no turn. Per-asset errors emit ScanFailed/SeizureFailed. The bounded Lens honors checked/result limits independently; stale borrower offsets are repaired within the visit, and successful defaults account for borrower-list compaction. Later Heart tasks remain runnable.

## Cursor recovery and comparison with RevenueDistributorTask

Each asset has `expiredAssetCursor` and `unhealthyAssetCursor`, both indexing its active-borrower
list. If either is nonzero, read one authoritative count and repair each stale offset independently.
A count failure preserves both saved offsets and stops the visit. A caught later failure retains
these repairs; a whole-body failure rolls them back.

Alternate the preferred discovery lane separately for each asset, starting with expiry. Persist
that turn outside the metered body so a reverted visit cannot monopolize one lane. Each lane uses
its independent offset and the configured check/result caps. Empty discovery falls through;
failed unhealthy discovery permits expiry fallback; failed expired discovery ends the visit.
A nonempty selection consumes the visit, whether its seizure succeeds or fails. The alternation
chooses which getter runs first; it does not restrict an empty visit to that selection. If both
getters would return candidates, repeated visits to the same asset attempt expired, unhealthy,
expired, unhealthy. An unhealthy-first visit can still settle expired debt when priced discovery
fails or returns no candidates. Asset rotation is independent of this per-asset order.
With assets added A then B and the asset index starting at A, four normal calls prefer
A expired, B expired, A unhealthy, B unhealthy. They do not process both priorities for A before
moving to B. Four calls cover both priorities for both assets, not necessarily every position:
each visit still respects the bounded check/result limits and makes at most one seizure attempt.
Priced discovery excludes expired debt and its failure preserves the unhealthy offset.

After successful settlement, rewind the executing lane by the selected borrower count, floored at
zero; end-of-list zero stays zero. Preserve the other lane's saved offset so continuing settlements
cannot repeatedly erase its traversal progress. The next visit repairs out-of-range offsets before
discovery; no extra count read follows settlement. Entries
swapped behind a valid cursor remain reachable on its next lap for a finite backlog. A rejected
selection advances one saved offset, wrapping using the authoritative population. An unhealthy
execution-price refresh failure instead leaves the unhealthy cursor unchanged. There is no second
seizure attempt. Governance can use the cursor setter and a smaller result limit to isolate a
persistently failing position from other selected borrowers.

At most one batch settles per visit. Each lane may inspect maxBorrowersToCheck entries, so two
different bounded pages can be examined. Each asset offers an unhealthy-first turn every second
visit, including during continuing expired arrivals. Existing combined Lens getters
retain their union behavior.

Catch boundaries: the two sequential Lens catches cover only their external discovery calls.
Ordinary Seize reverts are caught in the settlement helper as SeizureFailed. Unexpected local
failures, return-data copying failures or gas exhaustion escape to the metered self-call; outer
execute catches that failure, emits ExecutionFailed and rotates the asset using its reserve. All
body writes and events roll back on whole-body failure; the outer lane turn persists. The same periodic-task loop used by Heart
must continue to a later task. Own Kernel/HEART admission remains outside this operational boundary.
No Heart activation, freshness or gas configuration parameters change.

Expiry-positive pages never call priced discovery. A gas-consuming priced call can still return
through its catch when residual gas suffices: expiry progress remains and unhealthy progress is
retained. If the entire self-call exhausts gas, both cursor writes roll back and outer asset rotation
persists. Adequate configured gas remains a progress prerequisite.

| ID | Caller | Discovery / settlement condition | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-D01 | HEART | PRICE, backing, cache or stale-price outage; mixed page with unexpired prefix | Settle expired without invoking priced discovery; unexpired untouched; zero reward | Covered: [test][invariant_unexpiredDebtRemainsUnclassified], [test][test_givenMixedMaturity_givenOutage_whenHeartBeatsRepeat], [test][test_givenMixedMaturity_givenOutage_whenSinglePageScanned], [test][test_givenMixedMaturity_givenPriceReverts_whenExecuted], [test][test_givenMixedMaturity_givenBackingReverts_whenExecuted], [test][test_givenMixedMaturity_givenBackingPaused_whenExecuted], [test][test_givenMixedMaturity_givenPriceStale_whenExecuted], [test][test_givenMixedMaturity_givenCacheReverts_whenExecuted] |
| BLSEIZ-EXECUTE-P13 | HEART | Check/result limits 1; repeated visits; prefix pages, compaction, stale cursor and wrap | Advance empty pages, rewind successful batches, eventually settle all expired debt | Covered: [test][test_givenMixedMaturity_givenOutage_whenHeartBeatsRepeat]; [test][test_givenExpiredPopulation_givenOutage_whenBatchesCompact]; [test][test_givenStaleCursor_givenOutage_whenExecuted]; [test][invariant_unexpiredDebtRemainsUnclassified] |
| BLSEIZ-EXECUTE-D02 | HEART | All-expired page under PRICE/backing/cache outage; maturity equality included | Settle expired without priced scan; actual Treasury collateral, default accounting and membership reconcile; reward0 | Covered: [test][test_givenAllExpired_givenOutage_whenExecuted], [test][test_givenAllExpired_givenPriceReverts_whenExecuted], [test][test_givenAllExpired_givenBackingReverts_whenExecuted], [test][test_givenAllExpired_givenBackingPaused_whenExecuted], [test][test_givenAllExpired_givenPriceStale_whenExecuted], [test][test_givenAllExpired_givenCacheReverts_whenExecuted] |
| BLSEIZ-EXECUTE-D03 | HEART | FLOAN read failure in expiry discovery | Report exact failure; no priced scan; preserve borrower cursor, rotate assets | Covered: [test][test_givenExpiryCanonicalFailure_whenExecuted] |
| BLSEIZ-EXECUTE-D04 | HEART | Expiry-positive page; custody withdrawal fails during Seize | SeizureFailed(CustodyFailed); retain debt/custody; advance expiry offset one with wrap; restore/retry succeeds | Covered: [test][test_givenCustodyFailure_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-D05 | HEART | Arbitrary health/configuration failure in priced scan after an expiry-empty page | Report exact original selector; advance proven-empty expiry cursor without health classification | Covered: [test][test_givenHealthConfigurationFailure_whenExecuted] |
| BLSEIZ-EXECUTE-D06 | HEART | Custody preview fails in expiry quote | Report exact failure; no priced scan; no seizure; debt/cursor unchanged; restoration permits retry | Covered: [test][test_givenWithdrawalQuoteFailure_whenExecuted] |
| BLSEIZ-EXECUTE-D07 | HEART | Expiry scan succeeds; settlement helper exhausts gas copying a large Seize error | Outer ExecutionFailed; body/cursor rollback; asset rotation, next heartbeat and later Heart task preserved | Covered: [test][test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes] |
| BLSEIZ-EXECUTE-P14 | HEART | Prices usable, mixed expired/unexpired unhealthy debt | Expired-only batch first; priced unhealthy batch on a later visit | Covered: [test][test_givenPricesAvailable_whenMixedUnhealthyPageScanned] |
| BLSEIZ-EXECUTE-P15 | HEART task manager | Expired-containing page; PRICE consumes all forwarded gas if called | Settle expired without priced Lens/PRICE calls; later Heart task executes | Covered: [test][test_givenExpiredDebt_givenPriceConsumesGas_whenHeartRunsTasks] |
| BLSEIZ-EXECUTE-D08 | HEART task manager | Expiry-empty prefix; priced Lens consumes all forwarded gas | ScanFailed(0) with sufficient catch gas; expiry advances, unhealthy remains pending; asset rotates and later Heart task executes | Covered: [test][test_givenUnexpiredPrefix_givenPriceConsumesGas_whenHeartRunsTasks] |
| BLSEIZ-EXECUTE-D09 | HEART | Saved cursor becomes stale; active borrower count succeeds; expiry quote or settlement then fails | Persist zero repair after scan failure; singleton rejection advances one; retain debt and rotate | Covered: [test][test_givenStaleCursor_givenSettlementPaused_whenExecuted], [test][test_givenStaleCursor_givenRiskPaused_whenExecuted] |
| BLSEIZ-EXECUTE-P16 | HEART | Nonzero expiry-empty suffix and priced failure; filtered results empty | Use suffix cursor in the active borrower list, wrap and reach expired debt on later bounded visits | Covered: [test][test_givenExpiryEmptySuffix_givenOutage_whenHeartBeatsRepeat] |

ADMIN_ROLE and BURNER_LOANS_ADMIN_ROLE can use [setNextAssetIndex](./setNextAssetIndex.md) to choose the next managed asset, and [setExpiredAssetCursor](./setExpiredAssetCursor.md) or [setUnhealthyAssetCursor](./setUnhealthyAssetCursor.md) to recover one borrower lane independently. Recovery remains available while locally disabled. All recovery setters require the Task to be Kernel-active. Zero resets require no downstream reads; a nonzero borrower offset uses a zero-sized Lens scan for bounds validation.

[RevenueDistributorTask](../../../policies/RevenueDistributorTask.sol) advances its asset cursor before each distribution attempt, so a caught per-asset failure moves on. SeizerTask follows that rule for scan and settlement failures. Revenue may attempt several assets within one self-call; SeizerTask attempts one asset per heartbeat. On an entire self-call revert or gas exhaustion, Revenue's in-body cursor writes roll back and its outer execute only reports ExecutionFailed. SeizerTask deliberately advances outside the reverted body, preserving the next asset's turn. Borrower cursors and position accounting remain unchanged on whole-body failure.

| Failure boundary | SeizerTask next asset | RevenueDistributorTask next asset |
| --- | --- | --- |
| Per-asset error caught within a successful task body | Advance before attempt; keep movement | Advance before attempt; keep movement |
| Entire task body reverts or exhausts gas | Outer call advances one asset despite rollback | Cursor movement rolls back with body |

## Authorization

Fixed for this table: Accounting / events: Unchanged.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-A01 | Fuzz outside every HEART holder | Local enabled independently true/false | ROLES_RequireRole(HEART_ROLE) before no-op; no rotation | Covered: [test][test_whenCallerLacksHeartRole_reverts] |
| BLSEIZ-EXECUTE-A02 | Fuzz HEART_ROLE holder | Otherwise ready task | One asset turn admitted | Covered: [test][test_givenHeartRole_whenExecuted_thenAssetRotates] |

## Lifecycle

Fixed for this table: HEART and own Kernel activity are checked. No task-body registry/cursor/Lens/Seize reads.

| ID | Caller | Lifecycle state / history | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-L01 | HEART | Task disabled | Return without task call or rotation | Covered: [test][test_givenDisabled_whenExecuted_thenNoRotation], [test][test_givenUnequalCursors_givenDisabled_whenExecuted_thenBothArePreserved], [test][invariant_schedulerAndAccountingRemainConsistent] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P01 | HEART_ROLE holder | Enabled, no managed assets | Successful no-op | No work; asset iterator zero | Covered: [test][test_givenNoAssets_whenExecuted_thenNoWork] |
| BLSEIZ-EXECUTE-P02 | HEART | Scan/settlement errors caught inside self task | No outer ExecutionFailed if self task returns | Exact inner failure event; rotate; preserve borrower debt on rejected settlement | Covered: [test][test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn], [test][test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry] |

## Scanning and progress

Fixed for this table: Accounting / events: No selftask partial state; later Heart task still executes.

| ID | Caller | Cursor / gas / registry condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P03 | HEART | Entire self task exhausts its configured budget | ExecutionFailed(0); borrower state rolls back, asset rotation persists | Covered: [invariant][invariant_schedulerAndAccountingRemainConsistent], [test][test_givenWholeTaskExhaustsGas_whenExecuted_thenOtherAssetGetsNextHeartbeat] |
| BLSEIZ-EXECUTE-P09 | HEART | Self task reverts with a four-byte custom error | ExecutionFailed(selector); rotate assets | Covered: [test][test_givenSelfCallCustomError_whenExecuted_thenSelectorIsReported] |
| BLSEIZ-EXECUTE-P10 | HEART | Self task reverts with one byte 0xab | ExecutionFailed(0xab000000); zero-pad prefix; rotate assets | Covered: [test][test_givenSelfCallShortError_whenExecuted_thenPrefixIsZeroPadded] |
| BLSEIZ-EXECUTE-P11 | HEART | Self task reverts with 100,000 bytes beginning 0xabcdef01 | ExecutionFailed(0xabcdef01); copy only four bytes; rotate assets | Covered: [test][test_givenSelfCallLargeError_whenExecuted_thenOnlySelectorIsCopied] |
| BLSEIZ-EXECUTE-P12 | HEART | Next asset is the last managed asset; A already has a nonzero borrower cursor; entire B self-call reverts | Outer asset cursor wraps to0; both borrower cursors and principal unchanged | Covered: [test][test_givenLastAsset_whenSelfCallFails_thenRotationWrapsAndBorrowerCursorsStayUnchanged] |
| BLSEIZ-EXECUTE-P07 | HEART | Outer gas below configured body limit | Cap forwarding to retain cleanup; rotate despite bounded failure; no partial debt default | Covered: [test][test_givenOuterGasBelowConfiguredLimit_whenExecuted_thenCleanupAndRotationSurvive] |
| BLSEIZ-EXECUTE-P08 | HEART via task manager | Bounded self-call failure with another task following | Later periodic task executes once; asset rotation persists | Covered: [test][test_givenTaskExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes], [dependency gas exhaustion][test_givenLensExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes] |

## Own policy activity

Previously activated then Kernel-deactivated, retaining ROLES and valid caller authority; all direct operational dependencies/bindings remain ready. Inputs are valid. Restore Kernel membership then retry with a fresh valid input and assert the corresponding successful body effects; reactivation does not change positions or authorization. Use an unchanged-value seed too when the setter supports idempotence.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-L02 | Fuzz HEART_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Task) before HEART authentication | No task/cursor/dependency calls | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLSEIZ-EXECUTE-L03 | HEART_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Task) | No asset rotation or task body | Covered: [test][test_givenTaskInactive_whenExecuted_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |

## Shared assertions

Use existing task manager/later task fixture; prove bounded failing call returns sufficient gas for subsequent task rather than only asserting caught revert.

## Test organization

[execute.t.sol](./execute.t.sol) uses the shared Kernel/ROLES fixture with controlled dependency responses.
[execute integration tests](./integration/execute.t.sol) retain the real dependency and accounting interactions.

## Distinct registry progress outcomes

Task enabled; caller holds HEART; Core/Seize ready; sufficient bounded gas. Use fixed managed-asset fixtures so progress and skipped work are observable.

| ID | Caller | Managed assets / authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P04 | HEART_ROLE holder | Exactly one managed asset; task holds seizer role; expiry-empty, healthy priced result | Success | Expiry then priced discovery, no settlement; asset index0; each borrower cursor follows its own scan output | Covered: [test][test_givenOneAsset_whenExecuted_thenTraversalRemainsZero] |
| BLSEIZ-EXECUTE-P05 | HEART_ROLE holder | Exactly two assets; task holds seizer role | Success over repeated invocations | A batch 25; B turn; remaining A batch 25; no drain-before-rotation | Covered: [test][test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles], [test][test_givenHeartRole_whenExecuted_thenAssetRotates] |
| BLSEIZ-EXECUTE-P06 | HEART_ROLE holder | Two assets; task lacks seizer role | Successful bounded task with SeizerRoleMissing(asset) | Asset traversal advances; borrower cursor unchanged; no Lens scan; granting role restores scheduling | Covered: [test][test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates] |

## Distinct dependency-stage outcomes

Each row assumes an active/enabled Task, HEART caller, SEIZER grant and sufficient body gas. Preserve exact failure selectors and distinguish discovery from settlement errors. Outage fuzz families must guarantee PRICE revert, backing revert, backing pause, stale PRICE and cache revert seeds independently of maturity layout.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-D10 | HEART | All-unexpired page under pricing outage | ScanFailed(original pricing selector); advance/wrap expiry cursor, retain unhealthy cursor; no classification/settlement | Covered: [test][test_givenAllUnexpired_givenOutage_whenExecuted], [test][test_givenAllUnexpired_givenPriceReverts_whenExecuted], [test][test_givenAllUnexpired_givenBackingReverts_whenExecuted], [test][test_givenAllUnexpired_givenBackingPaused_whenExecuted], [test][test_givenAllUnexpired_givenPriceStale_whenExecuted], [test][test_givenAllUnexpired_givenCacheReverts_whenExecuted] |
| BLSEIZ-EXECUTE-D11 | HEART | Expiry-positive page; Risk active but locally disabled | ScanFailed(NotEnabled); retain cursor/debt; no priced or Seize call; restore/retry | Covered: [test][test_givenRiskPaused_whenExecuted] |
| BLSEIZ-EXECUTE-D12 | HEART | Expiry-positive page; Risk Kernel-inactive, enabled true/false independently | ScanFailed(PolicyNotActive); retain cursor/debt; no priced or Seize call | Covered: [test][test_givenRiskInactive_whenExecuted], [test][test_givenRiskInactivePaused_whenExecuted] |
| BLSEIZ-EXECUTE-D13 | HEART | Expiry-positive page; Seize active but locally paused | SeizureFailed(NotEnabled); retain debt; advance expiry offset one; restore/retry; unhealthy-first recovery may scan prices | Covered: [test][test_givenSeizePaused_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-D14 | HEART | Expiry-positive page; Core active/paused, inactive/enabled or inactive/paused; seed each | SeizureFailed(PolicyDependency_NotActive); retain debt; advance expiry offset one; restore/retry | Covered: [test][test_givenCoreUnavailable_givenOutage_whenExecuted], [test][test_givenCorePaused_whenLifecycleBoundarySeeded], [test][test_givenCoreInactiveEnabled_whenLifecycleBoundarySeeded], [test][test_givenCoreInactivePaused_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-D15 | HEART | Expiry-positive page; Seize Kernel-inactive; local enabled false/true | SeizureFailed(PolicyNotActive.selector), whose underlying error identifies Seize; no priced fallback; retain debt; advance expiry offset one | Covered: [test][test_givenSeizeInactive_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-D16 | HEART | Expiry-empty page; Risk active but disabled at priced snapshot | ScanFailed(NotEnabled); store expiry next and retain unhealthy offset, unlike an expiry quote failure | Covered: [test][test_givenExpiryEmptyPage_givenRiskPaused_whenExecuted] |
| BLSEIZ-EXECUTE-D17 | HEART | Expiry-empty page; Risk inactive at priced snapshot | ScanFailed(PolicyNotActive); store expiry next and retain unhealthy offset; no health classification or settlement | Covered: [test][test_givenExpiryEmptyPage_givenRiskInactive_whenExecuted] |
| BLSEIZ-EXECUTE-D18 | HEART | Expiry-empty page; valid prices and unhealthy candidate; priced custody preview fails | ScanFailed(original custody error); store expiry next and retain unhealthy offset; no Seize call; do not report healthy | Covered: [test][test_givenUnexpiredUnhealthyDebt_givenPricedCustodyQuoteFails_whenExecuted] |
| BLSEIZ-EXECUTE-D19 | HEART | Expiry-empty page; valid health selection; priced keeper-reward quote fails | ScanFailed(original quote error); store expiry next and retain unhealthy offset; no Seize call | Covered: [test][test_givenUnexpiredUnhealthyDebt_givenPricedRewardQuoteFails_whenExecuted] |
| BLSEIZ-EXECUTE-D20 | HEART | Lens succeeds with malformed return ABI at either discovery stage | Decode failure escapes external-call catch; outer ExecutionFailed, body rollback and asset rotation | Covered: [test][test_givenMalformedExpiryReturn_whenExecuted_thenOuterBoundaryRotates], [test][test_givenMalformedPricedReturn_whenExecuted_thenOuterBoundaryRotates] |

## Gas, maturity and callback boundaries

The outer reserve is50,000 gas at its budget checkpoint, not a guarantee for transactions too small to reach cleanup. Callback rows use an otherwise valid settlement so the attempted nested action reaches the intended admission guard.

| ID | Caller | Condition / domain | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P17 | HEART | At budget checkpoint availableGas<=50,000; nonempty registry; enough gas for cleanup | No self-call; ExecutionFailed(0); advance one asset; borrower/debt unchanged | Covered: [test][test_givenGasBelowReserve_whenExecuted_thenNoBodyAndOneRotation] |
| BLSEIZ-EXECUTE-P18 | HEART | At budget checkpoint availableGas<=50,000; empty registry; enough gas for cleanup | No self-call; ExecutionFailed(0); nextAssetIndex remains0 | Covered: [test][test_givenEmptyRegistry_givenGasBelowReserve_whenExecuted_thenNoBody] |
| BLSEIZ-EXECUTE-D21 | HEART | Self-call deliberately fails while registry empty | ExecutionFailed(selector); no modulo-by-zero or asset movement | Covered: [test][test_givenEmptyRegistry_givenBodyReverts_whenExecuted_thenFailureIsReported] |
| BLSEIZ-EXECUTE-D22 | HEART | HEART authentication succeeds; ROLES lookup for Task SEIZER grant fails inside body | Outer ExecutionFailed with original selector; borrower rollback and asset rotation | Covered: [test][test_givenTaskSeizerRoleReadFails_whenExecuted_thenOuterBoundaryRotates] |
| BLSEIZ-EXECUTE-P19 | HEART | One healthy position at maturity-1; prices valid | No expiry candidate; priced health checked normally; no seizure; exact progress | Covered: [test][test_givenHealthyDebtAtMaturityMinusOne_whenExecuted] |
| BLSEIZ-EXECUTE-P20 | HEART | One expired position at maturity+1; prices fail | One expiry settlement, no priced scan; exact debt/custody/default deltas | Covered: [test][test_givenExpiredDebtAtMaturityPlusOne_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-C01 | Seize/token callback caller without HEART | During valid outer settlement, nested execute() attempted and callback catches failure | Nested HEART role error; no nested progress; outer batch succeeds once and accounting reconciles | Covered: [test][test_givenCollateralCallback_whenNestedExecuteCaught_thenOuterBatchSettlesOnce] |
| BLSEIZ-EXECUTE-C02 | Seize/token callback caller | During valid outer settlement, nested selfExecuteTask() attempted and callback catches failure | OnlySelf; no nested task body; outer settlement and cursor update occur once | Covered: [test][test_givenCollateralCallback_whenNestedSelfCallCaught_thenOuterBatchSettlesOnce] |

## Missing scan capability

No compatibility/readiness failure is converted into successful health classification. The plain helper binding is immutable, so a wrong deployment requires replacement of the Task rather than a local Lens setter.

| ID | Caller | Dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-D23 | HEART | Accepted same-Core Lens lacks the expiry selector and reverts with empty bytes | ScanFailed(asset,0x00000000); no priced fallback or settlement; retain borrower cursor and rotate assets | Covered: [test][test_givenMissingExpirySelector_whenExecuted_thenNoPricedFallback] |

## Outer admission failures and actor identity

These failures occur before the metered self-call. Local pause does not bypass own activity or HEART authentication. The Lens reward actor is always the Task, independent of the external HEART caller.

| ID | Caller | Condition | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-T01 | HEART | Own Kernel activity lookup reverts with a fixed custom error | Exact Kernel error propagates; no task body, failure event or cursor rotation | Covered: [test][test_givenKernelActivityReadFails_whenExecuted_reverts] |
| BLSEIZ-EXECUTE-T02 | Otherwise authorized HEART | Own policy active; cached ROLES lookup reverts; local enabled independently false/true | Exact ROLES error propagates before disabled no-op; no body or rotation | Covered: [test][test_givenHeartRoleReadFails_whenExecuted_reverts] |
| BLSEIZ-EXECUTE-P21 | Fuzz HEART-only external caller without SEIZER | Task has SEIZER only; expired debt and pricing outage | Pass Task as Lens actor and Seize caller; expired settlement reward0 independent of external caller roles | Covered: [test][test_givenHeartOnlyCaller_givenTaskSeizerOnly_givenOutage_whenExecuted] |
| BLSEIZ-EXECUTE-P22 | HEART | Task has HEART but no SEIZER grant | SeizerRoleMissing(asset), no discovery or settlement; direct Seize role exemption does not bypass Task scheduling admission | Covered: [test][test_givenTaskHeartOnly_whenExecuted_thenSeizerGrantStillRequired] |

## Outage recovery and per-borrower reachability

Use real debt and custody. Set collateral prices so unexpired debt is independently proved underwater
before the outage. During the outage, only expired debt may settle. Restore price service without
advancing time to maturity, then prove every underwater borrower is revisited despite earlier expiry-only
pages, cursor rewind and list compaction. These finite-population cases do not assume continuing
expired arrivals or indefinitely gas-consuming pricing services.

| ID | Caller | Positions / cursor / outage | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLSEIZ-EXECUTE-P23 | HEART | Underwater prefix, expired middle, underwater suffix; PRICE/backing revert, paused backing, stale PRICE and unavailable cache; start0..2; full-width valid scan/result limits with 1/1 and MAX seeds | Only expired principal defaults during outage; direct unexpired seizure rejects unavailable prices; recovery revisits all underwater borrowers before their maturity, including those behind the saved cursor | Covered: [test][test_givenMixedUnderwaterDebt_givenOutage_whenPricesRecover], [test][test_givenMixedUnderwaterDebt_whenOutageCursorAndLimitBoundariesSeeded] |
| BLSEIZ-EXECUTE-P24 | HEART | Two expired borrowers before two underwater borrowers; check3/seize1; backing outage | Expired batches compact underwater entries into earlier slots; nonzero rewind does not strand them after recovery | Covered: [test][test_givenExpiredPrefix_givenUnderwaterSuffix_givenBackingOutage_whenPricesRecover] |
| BLSEIZ-EXECUTE-P25 | HEART | Cursor2 of4; external repayment swaps an underwater borrower behind the cursor while cursor2 remains valid in a population of3 | Outage scan wraps and finds expired debt; recovery revisits the moved borrower without a manual cursor reset | Covered: [test][test_givenExternalCompaction_givenCursorStillValid_whenPricesRecover] |
| BLSEIZ-EXECUTE-P26 | HEART | Cursor2 becomes stale after repayment shrinks population to2; one expired and one unexpired underwater borrower; backing outage | Repair then bounded outage progress settles expired debt; recovery settles the remaining underwater borrower before maturity | Covered: [test][test_givenStaleCursor_givenUnderwaterDebt_givenBackingOutage_whenPricesRecover] |
| BLSEIZ-EXECUTE-P27 | HEART | Nonzero cursor; expired batch rejects settlement during PRICE outage | Failed singleton preserves principal and advances expiry one; unhealthy cursor stays put during outage; both lanes drain after recovery | Covered: [test][test_givenFailedExpiredBatch_givenUnderwaterDebt_whenServicesRecover] |
| BLSEIZ-EXECUTE-P28 | HEART | Two unexpired underwater borrowers, no expired debt; check/seize1; PRICE outage | No default during outage; empty-expiry cursors advance and wrap; recovery settles both without admin cursor intervention | Covered: [test][test_givenOnlyUnderwaterDebt_givenPriceOutage_whenPricesRecover] |
| BLSEIZ-EXECUTE-P29 | HEART | Underwater, expired and healthy debt together; narrow pages; healthy tail moves into the deleted slot | Recovery scans past healthy debt, reaches both underwater borrowers, and preserves healthy debt and collateral | Covered: [test][test_givenHealthyAndUnderwaterDebt_givenOutage_whenPricesRecover] |
| BLSEIZ-EXECUTE-P30 | HEART | Underwater A, expired B, underwater C; check/result1; PRICE outage then recovery before maturity | Expiry lane passes A and seizes B during outage; unhealthy cursor stays0; first recovered priced batch seizes A while C remains pending | Covered: [test][test_givenUnderwaterPrefix_givenOutage_whenPricesRecover_thenFirstPricedBatchResumesPrefix] |
| BLSEIZ-EXECUTE-P31 | HEART and authorized handler | Eight expired and four future-maturity underwater loans; arbitrary bounded gas, page sizes, pause and independent cursor recovery; unequal initial offsets | Both cursor/accounting invariants hold; after every generated history restore operating state and adequate gas, preserve final offsets/order, drain with1/1 pages and no time advancement; every eligible loan/custody balance clears | Covered: [test][invariant_mixedBacklogRemainsReachable] |

## V12 F-6: lane fairness and rejected positions

Acceptance criteria: the first visit prefers expired debt; subsequent visits to each asset alternate
the preferred lane, including after an attempted gas-bounded rollback. Empty discovery and failed
unhealthy discovery may fall through; failed expiry discovery ends the visit. Each visit permits
one seizure attempt. A rejected selection advances that lane's saved offset by one, wrapping at the authoritative
population. Unhealthy snapshot/refresh failures retain its cursor. Successful removals retain
same-lane compaction recovery and preserve the other lane's valid traversal offset. Existing authorization, lifecycle, scan limits,
custody/accounting and Heart gas-isolation rows remain acceptance criteria.

| ID | Scenario | Required result | Test |
| --- | --- | --- | --- |
| BLSEIZ-EXECUTE-F601 | Persistent expired settlement rejection and eligible unhealthy debt | Unhealthy receives the next asset visit; rejected expiry advances one offset | Covered: [test][test_givenPersistentExpiredRejection_whenAssetVisitedAgain], [test][test_givenPersistentExpiredRejection_givenUnhealthyDebt_whenAssetVisitedAgain] |
| BLSEIZ-EXECUTE-F602 | Expired candidates replenished on every visit, including single-check pages | Unhealthy-first discovery every second visit; expiry cannot erase valid page progress; eligible debt settles before backlog exhaustion | Covered: [test][test_givenContinuingExpiredBatches_whenAssetVisitedAgain], [test][test_givenExpiredBacklog_givenUnhealthyDebt_whenAssetVisitedAgain], [test][test_givenExpiredPrefixAndTail_givenSingleCheckPages_whenVisitsRepeat], [test][test_givenExpiredBatch_givenOtherCursorBecomesStale_whenExecuted] |
| BLSEIZ-EXECUTE-F603 | Expired singleton cannot settle; interior, final and full-width offsets | With authoritative count, advance exactly one and wrap final offset; failed count retains offset for repair; no list/accounting mutation | Covered: [test][test_givenRejectedExpiredPosition_whenCursorAdvances], [test][test_givenRejectedExpiredPosition_whenCursorBoundariesSeeded], [test][test_givenRejectedPosition_givenPopulationReadFails_whenExecuted] |
| BLSEIZ-EXECUTE-F604 | Unhealthy singleton cannot settle after successful pricing | Advance exactly one without changing the other cursor | Covered: [test][test_givenRejectedUnhealthyPosition_whenExecuted], [test][test_givenUnhealthyBatchWithUnseizablePrefix_whenAssetVisitedAgain] |
| BLSEIZ-EXECUTE-F605 | Atomic batch contains a good prefix and unseizable tail | Rejected batch rolls back; no hidden retry; governance narrows the result limit and selects the good prefix for recovery | Covered: [test][test_givenRejectedExpiredBatch_whenExecuted_thenNoSingletonRetry], [test][test_givenExpiredBatchWithUnseizableTail_whenAdminRecoversCursor], [test][test_givenUnhealthyBatchWithUnseizableTail_whenAdminRecoversCursor] |
| BLSEIZ-EXECUTE-F606 | Expired or unhealthy batch rejects for a non-price reason | Advance one saved offset; retain the other lane cursor; one seizure attempt | Covered: [test][test_givenRejectedUnhealthyBatch_whenExecuted_thenNoSingletonRetry], [test][test_givenExpiredBatchWithUnseizablePrefix_whenAssetVisitedAgain], [test][test_givenUnhealthyBatchWithUnseizablePrefix_whenAssetVisitedAgain], [test][test_givenUnhealthyDebt_givenEmptySettlementRevert_whenTaskExecuted] |
| BLSEIZ-EXECUTE-F607 | PRICE/backing/cache discovery or execution refresh unavailable | Leave unhealthy cursor unchanged; no further seizure attempt; expiry remains runnable | Covered: [test][test_givenUnhealthyRefreshUnavailable_whenExecuted], [test][test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenSeized_reverts], [test][test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenTaskExecuted], [test][test_givenUnhealthyDebt_givenRefreshRevertsWithArguments_whenSeized_reverts], [test][test_givenUnhealthyDebt_givenEmptyRefreshRevert_whenTaskExecuted] |
| BLSEIZ-EXECUTE-F608 | Task body exhausts gas; two managed assets | Asset and per-asset lane turns persist; an even asset count cannot pin one lane | Covered: [test][test_givenTaskGasExhausted_whenAssetVisitedAgain], [test][test_givenPausedTask_whenReEnabled], [test][test_givenPreviouslyVisitedAsset_whenRemovedAndAdded] |
| BLSEIZ-EXECUTE-F609 | Eight expired or eight unexpired unhealthy loans; permanently rejected borrower between good loans; cursors1/5; check3/result2 | A persistently rejected batch requires governance recovery; after narrowing result limit to1 and resetting cursors, drain all good debt without maturing unhealthy loans; retain poisoned principal/custody and exact Treasury proceeds | Covered: [test][test_givenExpiredPoisonedBook_givenNonzeroCursors_whenVisitsRepeat], [test][test_givenUnhealthyPoisonedBook_givenNonzeroCursors_whenVisitsRepeat] |

The persistent-outage invariant also drains every generated history in `afterInvariant`, keeping the PRICE outage and both saved cursors intact. With 1/1 pages and sufficient task gas, all eight expired loans must default while only Carol and Dave remain active, with 2e9 principal due and 8e9 defaulted. Time is unchanged and priced discovery must still revert after the drain.

[invariant_schedulerAndAccountingRemainConsistent]: ./integration/progress.invariant.t.sol#L46
[test_givenDisabled_whenExecuted_thenNoRotation]: ./execute.t.sol#L110
[test_givenFiftyBorrowers_whenBatchLimitIsTwentyFive_thenAssetsRotateAndAllDebtSettles]: ./integration/execute.t.sol#L34
[test_givenHeartRole_whenExecuted_thenAssetRotates]: ./execute.t.sol#L211
[test_givenLastAsset_whenSelfCallFails_thenRotationWrapsAndBorrowerCursorsStayUnchanged]: ./integration/execute.t.sol#L399
[test_givenNoAssets_whenExecuted_thenNoWork]: ./execute.t.sol#L193
[test_givenOuterGasBelowConfiguredLimit_whenExecuted_thenCleanupAndRotationSurvive]: ./integration/execute.t.sol#L331
[test_givenScanReverts_whenExecuted_thenOtherAssetGetsNextTurn]: ./execute.t.sol#L87
[test_givenSeizerRoleMissing_whenExecuted_thenAssetStillRotates]: ./execute.t.sol#L143
[test_givenSeizureReverts_whenExecuted_thenEntireBatchRemainsForRetry]: ./integration/execute.t.sol#L266
[test_givenSelfCallCustomError_whenExecuted_thenSelectorIsReported]: ./execute.t.sol#L289
[test_givenSelfCallLargeError_whenExecuted_thenOnlySelectorIsCopied]: ./execute.t.sol#L311
[test_givenSelfCallShortError_whenExecuted_thenPrefixIsZeroPadded]: ./execute.t.sol#L302
[test_givenTaskExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes]: ./integration/execute.t.sol#L350
[test_givenTaskInactive_whenExecuted_reverts]: ./execute.t.sol#L220
[test_givenWholeTaskExhaustsGas_whenExecuted_thenOtherAssetGetsNextHeartbeat]: ./execute.t.sol#L61
[test_whenCallerLacksHeartRole_reverts]: ./execute.t.sol#L133
[test_givenOneAsset_whenExecuted_thenTraversalRemainsZero]: ./execute.t.sol#L434
[test_givenLensExhaustsGas_whenHeartRunsTasks_thenLaterTaskExecutes]: ./execute.t.sol#L29
[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: execute.t.sol#L458
[test_givenMixedMaturity_givenOutage_whenHeartBeatsRepeat]: ./integration/executeOracleOutage.t.sol#L560
[test_givenMixedMaturity_givenOutage_whenSinglePageScanned]: ./integration/executeOracleOutage.t.sol#L607
[test_givenAllExpired_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L622
[test_givenAllUnexpired_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L645
[test_givenExpiredPopulation_givenOutage_whenBatchesCompact]: ./integration/executeOracleOutage.t.sol#L686
[test_givenStaleCursor_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L723
[test_givenExpiryCanonicalFailure_whenExecuted]: ./integration/executeOracleOutage.t.sol#L864
[test_givenCustodyFailure_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L895
[test_givenRiskPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L949
[test_givenRiskInactive_whenExecuted]: ./integration/executeOracleOutage.t.sol#L960
[test_givenSeizePaused_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1012
[test_givenCoreUnavailable_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1038
[test_givenHealthConfigurationFailure_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1073
[test_givenWithdrawalQuoteFailure_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1099
[test_givenPricesAvailable_whenMixedUnhealthyPageScanned]: ./integration/executeOracleOutage.t.sol#L1138
[invariant_unexpiredDebtRemainsUnclassified]: ./integration/progressOracleOutage.invariant.t.sol#L32
[test_givenExpiredScan_givenHelperExhaustsGas_whenExecuted_thenLaterHeartTaskExecutes]: ./execute.t.sol#L234
[test_givenExpiredDebt_givenPriceConsumesGas_whenHeartRunsTasks]: ./integration/executeOracleOutage.t.sol#L1167
[test_givenUnexpiredPrefix_givenPriceConsumesGas_whenHeartRunsTasks]: ./integration/executeOracleOutage.t.sol#L1189
[test_givenStaleCursor_givenSettlementPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L763
[test_givenStaleCursor_givenRiskPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L775
[test_givenExpiryEmptySuffix_givenOutage_whenHeartBeatsRepeat]: ./integration/executeOracleOutage.t.sol#L824
[test_givenAllExpired_givenBackingPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1330
[test_givenAllExpired_givenBackingReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1325
[test_givenAllExpired_givenCacheReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1340
[test_givenAllExpired_givenPriceReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1320
[test_givenAllExpired_givenPriceStale_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1335
[test_givenAllUnexpired_givenBackingPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1355
[test_givenAllUnexpired_givenBackingReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1350
[test_givenAllUnexpired_givenCacheReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1365
[test_givenAllUnexpired_givenPriceReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1345
[test_givenAllUnexpired_givenPriceStale_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1360
[test_givenEmptyRegistry_givenBodyReverts_whenExecuted_thenFailureIsReported]: ./execute.t.sol#L765
[test_givenEmptyRegistry_givenGasBelowReserve_whenExecuted_thenNoBody]: ./execute.t.sol#L754
[test_givenExpiryEmptyPage_givenRiskInactive_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1424
[test_givenExpiryEmptyPage_givenRiskPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1402
[test_givenGasBelowReserve_whenExecuted_thenNoBodyAndOneRotation]: ./execute.t.sol#L735
[test_givenHeartOnlyCaller_givenTaskSeizerOnly_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1551
[test_givenHeartRoleReadFails_whenExecuted_reverts]: ./execute.t.sol#L819
[test_givenKernelActivityReadFails_whenExecuted_reverts]: ./execute.t.sol#L784
[test_givenMalformedExpiryReturn_whenExecuted_thenOuterBoundaryRotates]: ./execute.t.sol#L670
[test_givenMalformedPricedReturn_whenExecuted_thenOuterBoundaryRotates]: ./execute.t.sol#L690
[test_givenMissingExpirySelector_whenExecuted_thenNoPricedFallback]: ./execute.t.sol#L714
[test_givenMixedMaturity_givenBackingPaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1305
[test_givenMixedMaturity_givenBackingReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1298
[test_givenMixedMaturity_givenCacheReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1315
[test_givenMixedMaturity_givenPriceReverts_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1293
[test_givenMixedMaturity_givenPriceStale_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1310
[test_givenSeizeInactive_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1370
[test_givenTaskHeartOnly_whenExecuted_thenSeizerGrantStillRequired]: ./execute.t.sol#L797
[test_givenTaskSeizerRoleReadFails_whenExecuted_thenOuterBoundaryRotates]: ./execute.t.sol#L833
[test_givenUnexpiredUnhealthyDebt_givenPricedCustodyQuoteFails_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1456
[test_givenUnexpiredUnhealthyDebt_givenPricedRewardQuoteFails_whenExecuted]: ./integration/executeOracleOutage.t.sol#L1484
[test_givenCollateralCallback_whenNestedExecuteCaught_thenOuterBatchSettlesOnce]: ./integration/executeOracleOutage.t.sol#L2245
[test_givenCollateralCallback_whenNestedSelfCallCaught_thenOuterBatchSettlesOnce]: ./integration/executeOracleOutage.t.sol#L2265
[test_givenCoreInactiveEnabled_whenLifecycleBoundarySeeded]: ./integration/executeOracleOutage.t.sol#L2154
[test_givenCoreInactivePaused_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L2159
[test_givenCorePaused_whenLifecycleBoundarySeeded]: ./integration/executeOracleOutage.t.sol#L2149
[test_givenExpiredDebtAtMaturityPlusOne_givenOutage_whenExecuted]: ./integration/executeOracleOutage.t.sol#L2217
[test_givenHealthyDebtAtMaturityMinusOne_whenExecuted]: ./integration/executeOracleOutage.t.sol#L2190
[test_givenRiskInactivePaused_whenExecuted]: ./integration/executeOracleOutage.t.sol#L2118
[test_givenExpiredPrefix_givenUnderwaterSuffix_givenBackingOutage_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1651
[test_givenExternalCompaction_givenCursorStillValid_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1693
[test_givenFailedExpiredBatch_givenUnderwaterDebt_whenServicesRecover]: ./integration/executeOracleOutage.t.sol#L1801
[test_givenHealthyAndUnderwaterDebt_givenOutage_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1895
[test_givenMixedUnderwaterDebt_givenOutage_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1601
[test_givenMixedUnderwaterDebt_whenOutageCursorAndLimitBoundariesSeeded]: ./integration/executeOracleOutage.t.sol#L1632
[test_givenOnlyUnderwaterDebt_givenPriceOutage_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1855
[test_givenStaleCursor_givenUnderwaterDebt_givenBackingOutage_whenPricesRecover]: ./integration/executeOracleOutage.t.sol#L1725

[test_givenUnequalCursors_givenDisabled_whenExecuted_thenBothArePreserved]: execute.t.sol#L1054
[test_givenUnderwaterPrefix_givenOutage_whenPricesRecover_thenFirstPricedBatchResumesPrefix]: integration/executeOracleOutage.t.sol#L1574

[invariant_mixedBacklogRemainsReachable]: integration/progressMixedMaturity.invariant.t.sol#L50
[test_givenPersistentExpiredRejection_whenAssetVisitedAgain]: ./execute.t.sol#L1194
[test_givenContinuingExpiredBatches_whenAssetVisitedAgain]: ./execute.t.sol#L1215
[test_givenRejectedExpiredPosition_whenCursorAdvances]: ./execute.t.sol#L1231
[test_givenRejectedExpiredPosition_whenCursorBoundariesSeeded]: ./execute.t.sol#L1256
[test_givenRejectedUnhealthyPosition_whenExecuted]: ./execute.t.sol#L1263
[test_givenRejectedExpiredBatch_whenExecuted_thenNoSingletonRetry]: ./execute.t.sol#L1286
[test_givenRejectedUnhealthyBatch_whenExecuted_thenNoSingletonRetry]: ./execute.t.sol#L1310
[test_givenUnhealthyRefreshUnavailable_whenExecuted]: ./execute.t.sol#L1339
[test_givenTaskGasExhausted_whenAssetVisitedAgain]: ./execute.t.sol#L1369
[test_givenPausedTask_whenReEnabled]: ./execute.t.sol#L1387
[test_givenPreviouslyVisitedAsset_whenRemovedAndAdded]: ./execute.t.sol#L1404
[test_givenRejectedPosition_givenPopulationReadFails_whenExecuted]: ./execute.t.sol#L1416
[test_givenPersistentExpiredRejection_givenUnhealthyDebt_whenAssetVisitedAgain]: ./integration/executeOracleOutage.t.sol#L166
[test_givenExpiredBacklog_givenUnhealthyDebt_whenAssetVisitedAgain]: ./integration/executeOracleOutage.t.sol#L214
[test_givenExpiredBatchWithUnseizableTail_whenAdminRecoversCursor]: ./integration/executeOracleOutage.t.sol#L278
[test_givenExpiredBatchWithUnseizablePrefix_whenAssetVisitedAgain]: ./integration/executeOracleOutage.t.sol#L332
[test_givenUnhealthyBatchWithUnseizablePrefix_whenAssetVisitedAgain]: ./integration/executeOracleOutage.t.sol#L375
[test_givenUnhealthyBatchWithUnseizableTail_whenAdminRecoversCursor]: ./integration/executeOracleOutage.t.sol#L425
[test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenSeized_reverts]: ./integration/executeOracleOutage.t.sol#L507
[test_givenUnhealthyDebt_givenRefreshOnlyOutage_whenTaskExecuted]: ./integration/executeOracleOutage.t.sol#L526
[test_givenExpiredPrefixAndTail_givenSingleCheckPages_whenVisitsRepeat]: ./integration/executeOracleOutage.t.sol#L246
[test_givenExpiredBatch_givenOtherCursorBecomesStale_whenExecuted]: ./execute.t.sol#L1438
[test_givenExpiredPoisonedBook_givenNonzeroCursors_whenVisitsRepeat]: ./integration/executeOracleOutage.t.sol#L95
[test_givenUnhealthyPoisonedBook_givenNonzeroCursors_whenVisitsRepeat]: ./integration/executeOracleOutage.t.sol#L102
[test_givenUnhealthyDebt_givenRefreshRevertsWithArguments_whenSeized_reverts]: ./integration/executeOracleOutage.t.sol#L483
[test_givenUnhealthyDebt_givenEmptySettlementRevert_whenTaskExecuted]: ./integration/executeOracleOutage.t.sol#L72
[test_givenUnhealthyDebt_givenEmptyRefreshRevert_whenTaskExecuted]: ./integration/executeOracleOutage.t.sol#L50

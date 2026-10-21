# RevenueDistributorTask.execute scenario plan

Scope: Heart entry point, gas-isolated self-call, per-asset failure handling and progress. [selfExecuteTask](./selfExecuteTask.md) owns the direct-call boundary.

An authorized execute call returns silently while RDTask itself is Kernel-inactive or locally disabled, before making its self-call. Heart role membership is independent of policy activation.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

RDTask = RevenueDistributorTask; RD = RevenueDistributor. Only HEART_ROLE may call execute; fuzz
other callers excluding every Heart role holder. execute checks Heart authority even when task is
disabled; a disabled task returns successfully. execute returns silently when RD is Kernel-inactive
or locally disabled, without querying its Active set. An enabled task with an available RD attempts
`distribute`; per-asset reverts are caught and emitted as `AssetDistributionFailed`. An empty Active
set is also a silent enabled-task no-op.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. With enough gas, visit each current Active asset at most once, starting at cursor modulo asset count; settle authoritative recipient/custody amounts. Store next cursor before each isolated distribution attempt, including failures. Observe exact AssetDistributionFailed(asset,firstFourReasonBytes) versus RD fail-soft DistributionDeferred; an outer self-call failure emits ExecutionFailed(firstFourReasonBytes) and rolls back its internal work.

## Authorization

| ID | Caller | Task Kernel | Task local | RD Kernel/local | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-A01 | Any caller without HEART_ROLE, fuzz | Active or inactive | Enabled or disabled | Independently fuzz active/inactive and enabled/disabled | ROLES_RequireRole(HEART_ROLE) before every lifecycle branch | Unchanged | Covered: [test][test_whenCallerLacksHeartRole_revertsBeforeLifecycleChecks] |

## Lifecycle

| ID | Task Kernel | Task local | RD Kernel | RD local | RD active assets/receipts | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-P01 | Active | Disabled | Active or inactive | Enabled or disabled | Fuzz empty/nonempty and zero/positive receipts | Silent success without querying RD | Balances and cursor retained; no call/event | Covered: [test][test_givenTaskDisabled_executeDoesNotQueryDistributor] |
| TASK-P02 | Active | Enabled | Active | Disabled | Fuzz one/multiple Active assets with positive receipts | Silent success without querying the Active set | Balances and cursor retained; no call/event | Covered: [test][test_givenDistributorUnavailable_whenHeartExecutes] |
| TASK-P07 | Active | Enabled | Inactive | Enabled | Fuzz one/multiple Active assets with positive receipts | Silent success before querying RD local state or the Active set | Balances and cursor retained; no call/event | Covered: [test][test_givenDistributorUnavailable_whenHeartExecutes] |
| TASK-P13 | Active | Enabled | Inactive | Disabled | Fuzz one/multiple Active assets with positive receipts | Silent success before querying RD local state or the Active set | Balances and cursor retained; no call/event | Covered: [test][test_givenDistributorUnavailable_whenHeartExecutes] |
| TASK-P08 | Active | Enabled | Active | Enabled | Empty | Silent success | Cursor and balances retained; no ExecutionFailed, AssetDistributionFailed, Distributed or token transfer event | Covered: [test][test_givenNoActiveAssets_executeIsSilentAndPreservesCursor] |
| TASK-P03 | Inactive | Enabled or disabled | Active | Enabled | Nonempty with positive receipts | Silent success without querying RD | No self-call, payment, cursor change or failure event | Covered: [test][test_givenTaskInactive_executeDoesNotQueryDistributor] |

## Asset traversal

| ID | Caller | Active asset count | Starting cursor | Asset-set transition | Gas budget | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-P04 | Heart | 1 | 0 | None | Enough for all | Visit the asset exactly once | Correct payout; cursor wraps to zero | Covered: [test][test_givenOneActiveAsset_executeVisitsItOnce] |
| TASK-P09 | Heart | 2 | 0 | None | Enough for all | Visit both exactly once in order | Correct per-asset payouts; cursor wraps | Covered: [test][test_givenTwoActiveAssets_executeVisitsEachInOrder] |
| TASK-P10 | Heart | 13 | Fuzz 1..12 | None | Enough for all | Visit every indexed asset exactly once | Exactly one indexed lookup and correct payout per asset; cursor returns to its start | Covered: [test][test_givenThirteenActiveAssets_executeVisitsCircularOrder] |
| TASK-P11 | Heart | 13 | Fuzz 1..12 | None | Enough for all | Begin at cursor, wrap from index 12 to zero, and stop before repeating the starting index | Exact circular lookup/event order and final cursor | Covered: [test][test_givenThirteenActiveAssets_executeVisitsCircularOrder] |
| TASK-P12 | Heart | Multiple before and after | Out of range after retirement | Selected asset retired | Enough for all remaining | Normalize cursor modulo current count | Visit each remaining asset once without out-of-range access | Covered: [test][test_givenCursorOutOfRangeAfterRetirement_executeNormalizesTraversal] |

## Gas and cursor progress

| ID | Caller | Active assets | Starting cursor | `minimumGasToAttempt` | `gasReserve` | Per-attempt behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-P05 | Heart | Multiple | Fuzz valid | Configured below initial budget | Configured | Budget permits some but not all; repeated beats, no config change | Pause with cursor at first unattempted index; eventually settle every asset | No asset starvation | Covered: [test][test_givenLimitedExecutionGas_repeatedBeatsSettleEveryAsset] |
| TASK-T03 | Heart | First gas-burning; later valid | First asset | Valid | Retained | First token transfer exhausts its forwarded gas and RD defers the Treasury share; next beat reaches later asset | Advance cursor past attempted asset without an AssetDistributionFailed event | Earlier debt remains retryable; later asset progresses | Covered: [evidence][test_givenFirstAssetBurnsGas_nextBeatSettlesLaterAsset] |
| TASK-G01 | Heart | At least one unattempted | Next asset | Exact threshold | Configured | Gas entering next attempt at/below threshold, then sufficient after configuration is lowered | Stop before querying next asset when threshold not exceeded; later execution may proceed | No cursor advance without an attempted asset | Covered: [test][test_givenAttemptThresholdConsumesBudget_executeStopsBeforeLookup] |
| TASK-G02 | Heart | Two with receipts | First | Below initial budget | 100,000 | First asset settles; second indexed lookup returns normally after consuming the reserve | Stop after lookup without attempting second distribution; later beat resumes | Earlier settlement commits; cursor stays at second asset; no failure event | Covered: [lookup cutoff and continuation][test_givenIndexedLookupConsumesReserve_executePausesThenResumes] |

## Token transfer failure

| ID | Caller | First asset route/debt | First token behavior | Later asset state | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-T01 | Heart | Positive distributable share | Transfer returns false or reverts and RD catches it | Active with valid token and receipts | RD defers failed share; no AssetDistributionFailed because RD call succeeds; later settles | Failed debt retained, later payout independent | Covered: [test][test_givenTokenTransferFails_taskDefersShareAndContinues] |

## Distribution call failure

| ID | Caller | Failing asset revert data | Later asset state | Remaining gas | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-T02 | Heart | Custom error selector | Active/valid | Enough to continue | AssetDistributionFailed with the four-byte selector; continue | Failing asset rolled back; later assets can settle | Covered: [test][test_givenDistributionRevertsWithSelector_taskEmitsSelectorAndContinues] |
| TASK-T05 | Heart | Empty | Active/valid | Enough to continue | AssetDistributionFailed(0x00000000); continue | Failing asset rolled back; later assets can settle | Covered: [test][test_givenDistributionRevertsWithoutData_taskEmitsZeroAndContinues] |
| TASK-T06 | Heart | Longer than four bytes | Active/valid | Enough to continue | AssetDistributionFailed with only the first four bytes; continue | Failing asset rolled back; later assets can settle | Covered: [test][test_givenDistributionRevertsWithLongData_taskEmitsFirstFourBytes] |

## Self-call failure

| ID | Caller | `executionGasLimit` | Failure point | Earlier internal work | Revert data | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-T04 | Heart | 1 | Self-call entry/out of gas | None | Empty | ExecutionFailed(0x00000000) | Whole failed self-call rolls back cursor and payments | Covered: [test][test_givenInsufficientSelfCallGas_executeEmitsFailureAndRollsBack] |
| TASK-T07 | Heart | Sufficient | Active-list getter before settlement | None | Custom error | ExecutionFailed with the first four error bytes | Whole self-call rolls back; cursor and balances unchanged | Covered: [test][test_givenAssetCountGetterReverts_executeEmitsFailure] |
| TASK-T08 | Heart | Sufficient | Indexed getter after an earlier settlement | One payment and cursor advance | Custom error | ExecutionFailed with the first four error bytes | Whole self-call rolls back cursor and the earlier payment | Covered: [test][test_givenLaterAssetGetterReverts_executeRollsBackEarlierSettlement] |

## BL payout separation

| ID | Caller | RDTask state | RD state/receipts | BL state | BL pending bucket | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-P06 | Heart with role retained | Active/enabled | Active/enabled; positive receipts | Independently active or inactive | Deferred fee | Task settles RD custody only; BL fee remains owed until explicit BL retry | No call to BL.transferPendingPayout; BL buckets/indexes unchanged by task; later retry delivers fee once | Covered: [test][test_givenBurnerLoansPendingFee_taskSettlesOnlyDistributorCustody] |

Existing [Heart/BL regression](../BurnerLoans/transferPendingPayout.t.sol#L1290) exercises BurnerLoansYieldClaimer and cannot establish RDTask behavior. RDT is the configuration timelock; RDTask is the Heart execution task.

[test_whenCallerLacksHeartRole_revertsBeforeLifecycleChecks]: ./execute.t.sol#L58
[test_givenTaskDisabled_executeDoesNotQueryDistributor]: ./execute.t.sol#L80
[test_givenDistributorUnavailable_whenHeartExecutes]: ./execute.t.sol#L117
[test_givenNoActiveAssets_executeIsSilentAndPreservesCursor]: ./execute.t.sol#L155
[test_givenTaskInactive_executeDoesNotQueryDistributor]: ./execute.t.sol#L173
[test_givenOneActiveAsset_executeVisitsItOnce]: ./execute.t.sol#L197
[test_givenTwoActiveAssets_executeVisitsEachInOrder]: ./execute.t.sol#L210
[test_givenThirteenActiveAssets_executeVisitsCircularOrder]: ./execute.t.sol#L224
[test_givenCursorOutOfRangeAfterRetirement_executeNormalizesTraversal]: ./execute.t.sol#L253
[test_givenLimitedExecutionGas_repeatedBeatsSettleEveryAsset]: ./execute.t.sol#L284
[test_givenAttemptThresholdConsumesBudget_executeStopsBeforeLookup]: ./execute.t.sol#L311
[test_givenFirstAssetBurnsGas_nextBeatSettlesLaterAsset]: ./execute.t.sol#L416
[test_givenTokenTransferFails_taskDefersShareAndContinues]: ./execute.t.sol#L453
[test_givenDistributionRevertsWithSelector_taskEmitsSelectorAndContinues]: ./execute.t.sol#L498
[test_givenDistributionRevertsWithoutData_taskEmitsZeroAndContinues]: ./execute.t.sol#L503
[test_givenDistributionRevertsWithLongData_taskEmitsFirstFourBytes]: ./execute.t.sol#L508
[test_givenInsufficientSelfCallGas_executeEmitsFailureAndRollsBack]: ./execute.t.sol#L515
[test_givenAssetCountGetterReverts_executeEmitsFailure]: ./execute.t.sol#L541
[test_givenLaterAssetGetterReverts_executeRollsBackEarlierSettlement]: ./execute.t.sol#L559
[test_givenBurnerLoansPendingFee_taskSettlesOnlyDistributorCustody]: ./executeBurnerLoansSeparation.t.sol#L16
[test_givenIndexedLookupConsumesReserve_executePausesThenResumes]: ./execute.t.sol#L334

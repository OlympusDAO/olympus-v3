# PriceCacherTask.execute coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-EXECUTE`.

HEART_ROLE is the complete external caller set. Own Kernel activity is required before
HEART authorization and the disabled no-op. When enabled, the task budgets gas for
its self-call and each pair, reserves cleanup gas, and copies up to four return bytes per
call. Failed calls emit `ExecutionFailed` or `PairCacheFailed` with the first four revert
bytes, or zero for an empty failure such as a callee running out of gas. Each pair uses
`maxAge=0`. Each execution starts with the first pair in stored order. If the remaining
gas is too low, `ExecutionDeferred` identifies the first skipped index. Later pairs can
remain stale if the configured limits cannot cover the full list.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-A01 | Fuzz callers excluding every HEART holder | true | true | Caller lacks HEART_ROLE | ROLES_RequireRole(HEART_ROLE) | Covered: [test][test_whenCallerDoesNotHaveHeartRole_reverts] |
| PCACHER-EXECUTE-A02 | Fuzz HEART holders | true | true | Fuzz arbitrary HEART holders | Refresh configured pairs; forwarding independent of caller identity | Covered: [test][test_whenHeartAndCollectionVary_thenExactAttempts] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-L01 | HEART | true | false | Task paused | Return without cache calls | Covered: [test][test_givenDisabled_isNoOp] |
| PCACHER-EXECUTE-L02 | HEART | false | true | Task Kernel-inactive but enabled | PriceCacherTask_PolicyInactive(subject); unchanged | Covered: [test][test_givenInactive_whenExecuted_reverts] |
| PCACHER-EXECUTE-L03 | HEART | false | false | Both task inactive and paused | PriceCacherTask_PolicyInactive(subject) before disabled no-op; unchanged | Covered: [test][test_givenInactive_whenExecuted_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-D01 | HEART | true | true | Cache inactive/enabled | Self-call reverts PolicyDependency_NotActive(cache); outer emits ExecutionFailed(selector) and returns; no cache calls | Covered: [test][test_givenPriceCacheIsInactive_reportsFailure] |
| PCACHER-EXECUTE-D02 | HEART | true | true | Cache active/disabled | Self-call reverts PolicyDependency_NotActive(cache); outer emits ExecutionFailed(selector) and returns; no cache calls | Covered: [test][test_givenPriceCacheIsDisabled_reportsFailure] |
| PCACHER-EXECUTE-D03 | HEART | true | true | Cache inactive/disabled | Self-call reverts PolicyDependency_NotActive(cache); outer emits ExecutionFailed(selector) and returns; no cache calls | Covered: [test][test_givenCacheInactiveDisabled_whenExecuted_thenFailureAndNoCalls] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-N01 | HEART | true | true | Zero to four fixture pairs fit the task budget | Zero work for empty; one attempt per entry; no array mutation | Covered: [test][test_whenHeartAndCollectionVary_thenExactAttempts], [test][test_whenEmptyPairSet_thenNoCacheCalls], [test][test_whenSinglePair_thenOneCacheCall] |
| PCACHER-EXECUTE-N02 | HEART | true | true | 32 fixture pairs exceed the task budget | Refresh a nonempty prefix in stored order and emit ExecutionDeferred with the first skipped pair index | Covered: [test][test_givenLargePairSet_whenExecuted_thenReportsDeferredWork] |
| PCACHER-EXECUTE-N03 | HEART | true | true | Available gas allows one of two fixture pairs to finish | On both executions, refresh the first pair and emit ExecutionDeferred(1) | Covered: [test][test_whenGasAllowsOnePair_thenEachExecutionStartsAtFirstPair] |
| PCACHER-EXECUTE-N04 | HEART | true | true | Available gas cannot fund one pair attempt | Emit ExecutionDeferred(0) and return without a pair call | Covered: [test][test_whenGasCannotFundAPair_thenReportsDeferral] |
| PCACHER-EXECUTE-N05 | HEART | true | true | First pair is removed after index 1 is skipped | Start at index zero in the updated list and refresh the remaining pair | Covered: [test][test_givenPairRemovedAfterDeferral_whenExecuted_thenStartsAtRemainingPair] |
| PCACHER-EXECUTE-N06 | HEART | true | true | Only cleanup gas is available | Emit ExecutionDeferred(0) and return without starting the self-call | Covered: [test][test_whenGasCannotFundSelfCall_thenReportsDeferralWithoutCalling] |
| PCACHER-EXECUTE-N07 | HEART | true | true | Three pairs, aggregate limit initially covers two | Emit ExecutionDeferred(2). After the limit is raised, refresh all three starting from index zero | Covered: [test][test_givenThreePairs_whenExecutionLimitIsRaised_thenAllPairsRefresh] |
| PCACHER-EXECUTE-N08 | HEART | true | true | Pair limit of one gas, then a sufficient limit | Report both failed calls with a zero selector. With enough gas, refresh both pairs | Covered: [test][test_whenPairGasLimitIsExhausted_thenReportsEachFailure] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-P01 | HEART | true | true | Two operational configured pairs | Attempt in stored order with exact identities, maxAge=0, and the defined call gas limits | Covered: [test][test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder] |
| PCACHER-EXECUTE-P02 | HEART | true | true | After local reEnable or Kernel reactivation | Normal work resumes; preserve configuration | Covered: [test][test_givenReEnabled_whenExecuted_thenNormalWork], [test][test_givenReactivated_whenExecuted_thenNormalWork] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-T01 | HEART | true | true | Cache status getter reverts | ExecutionFailed(exact first4bytes); outer returns; no cache calls | Covered: [test][test_givenPriceCacheEnabledQueryReverts_emitsFailureAndReturns] |
| PCACHER-EXECUTE-T02 | HEART | true | true | First pair reverts | Exact PairCacheFailed event; next pair succeeds once | Covered: [test][test_givenFirstPairReverts_attemptsSecondPair] |
| PCACHER-EXECUTE-T03 | HEART | true | true | First pair becomes unsupported | Exact event; next pair succeeds | Covered: [test][test_givenConfiguredPairBecomesUnsupported_attemptsNextPairWithoutReverting] |
| PCACHER-EXECUTE-T04 | HEART | true | true | Second pair reverts | Keep earlier successful cache update; exact failure event | Covered: [test][test_givenSecondPairReverts_preservesFirstPair] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional authorization and boundary cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-A03 | Fuzz callers excluding every HEART holder | true | false | Task paused; caller lacks HEART_ROLE | ROLES_RequireRole(HEART_ROLE) before disabled no-op; unchanged | Covered: [test][test_givenDisabled_whenUnauthorizedCallerExecutes_reverts] |
| PCACHER-EXECUTE-T05 | HEART | true | true | Cache status getter reverts with empty data | ExecutionFailed(0x00000000); no cache writes | Covered: [test][test_givenEmptyStatusError_whenExecuted_thenZeroSelector] |
| PCACHER-EXECUTE-T06 | HEART | true | true | Cache status getter reverts with 1,2,3 bytes | ExecutionFailed with exact right-zero-padded bytes4; no cache writes | Covered: [test][test_givenShortStatusErrors_whenExecuted_thenPaddedSelectors] |
| PCACHER-EXECUTE-T07 | HEART | true | true | Cache status getter reverts with 4096 bytes beginning deadbeef | ExecutionFailed(0xdeadbeef); no cache writes; adequate transaction gas assumed | Covered: [test][test_givenLargeStatusError_whenExecuted_thenPrefixOnly] |
| PCACHER-EXECUTE-T08 | HEART | true | true | First pair reverts with empty data | PairCacheFailed exact target/pair and zero selector; second pair updates exactly once | Covered: [test][test_givenEmptyPairError_whenExecuted_thenNextPairSucceeds] |
| PCACHER-EXECUTE-T09 | HEART | true | true | First pair reverts with one byte aa | PairCacheFailed exact target/pair and aa000000; second pair updates exactly once | Covered: [test][test_givenShortPairError_whenExecuted_thenNextPairSucceeds] |
| PCACHER-EXECUTE-T10 | HEART | true | true | First pair reverts with 4096 bytes beginning deadbeef | PairCacheFailed exact target/pair and deadbeef; second pair updates once with adequate transaction gas | Covered: [test][test_givenLargePairError_whenExecuted_thenNextPairSucceeds] |

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-L04 | Any address, fuzz, without authorization exclusions | false | false | Task paused, then Kernel-deactivated; existing cache/pair fixture retained; No arguments; activity precedes Heart-role check and disabled no-op | `PriceCacherTask_PolicyInactive(task)` before caller, input and dependency checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst] |

[test_givenCacheInactiveDisabled_whenExecuted_thenFailureAndNoCalls]: execute.t.sol#L333
[test_givenConfiguredPairBecomesUnsupported_attemptsNextPairWithoutReverting]: execute.t.sol#L139
[test_givenDisabled_isNoOp]: execute.t.sol#L33
[test_givenDisabled_whenUnauthorizedCallerExecutes_reverts]: execute.t.sol#L362
[test_givenEmptyPairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L391
[test_givenEmptyStatusError_whenExecuted_thenZeroSelector]: execute.t.sol#L374
[test_givenFirstPairReverts_attemptsSecondPair]: execute.t.sol#L118
[test_givenInactive_whenExecuted_reverts]: execute.t.sol#L319
[test_givenLargePairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L401
[test_givenLargeStatusError_whenExecuted_thenPrefixOnly]: execute.t.sol#L386
[test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder]: execute.t.sol#L93
[test_givenPriceCacheEnabledQueryReverts_emitsFailureAndReturns]: execute.t.sol#L78
[test_givenPriceCacheIsDisabled_reportsFailure]: execute.t.sol#L63
[test_givenPriceCacheIsInactive_reportsFailure]: execute.t.sol#L47
[test_givenReEnabled_whenExecuted_thenNormalWork]: execute.t.sol#L344
[test_givenReactivated_whenExecuted_thenNormalWork]: execute.t.sol#L353
[test_givenSecondPairReverts_preservesFirstPair]: execute.t.sol#L160
[test_givenShortPairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L396
[test_givenShortStatusErrors_whenExecuted_thenPaddedSelectors]: execute.t.sol#L379
[test_whenCallerDoesNotHaveHeartRole_reverts]: execute.t.sol#L22
[test_whenEmptyPairSet_thenNoCacheCalls]: execute.t.sol#L188
[test_whenHeartAndCollectionVary_thenExactAttempts]: execute.t.sol#L178
[test_givenLargePairSet_whenExecuted_thenReportsDeferredWork]: execute.t.sol#L198
[test_whenGasAllowsOnePair_thenEachExecutionStartsAtFirstPair]: execute.t.sol#L223
[test_whenGasCannotFundAPair_thenReportsDeferral]: execute.t.sol#L242
[test_whenGasCannotFundSelfCall_thenReportsDeferralWithoutCalling]: execute.t.sol#L252
[test_givenPairRemovedAfterDeferral_whenExecuted_thenStartsAtRemainingPair]: execute.t.sol#L261
[test_givenThreePairs_whenExecutionLimitIsRaised_thenAllPairsRefresh]: execute.t.sol#L275
[test_whenPairGasLimitIsExhausted_thenReportsEachFailure]: execute.t.sol#L299
[test_whenSinglePair_thenOneCacheCall]: execute.t.sol#L193
[test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst]: ./execute.t.sol#L446

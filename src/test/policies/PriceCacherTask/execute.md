# PriceCacherTask.execute coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-EXECUTE`.

HEART_ROLE is the complete external caller set. The outer scheduler returns while
disabled, invokes selfExecuteTask through an external self-call, and catches ordinary
aggregate failures as ExecutionFailed(first4bytes). Own Kernel activity is required before
HEART authorization and the disabled no-op. Per-pair calls use maxAge=0 and
are unbounded in gas; this plan does not promise gas-exhaustion isolation.

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
| PCACHER-EXECUTE-N01 | HEART | true | true | Empty and single pair sets; larger fixture set | Zero work for empty; one attempt per entry; no array mutation | Covered: [test][test_whenHeartAndCollectionVary_thenExactAttempts], [test][test_whenEmptyPairSet_thenNoCacheCalls], [test][test_whenSinglePair_thenOneCacheCall], [test][test_whenLargerPairSet_thenAllCacheCalls] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-P01 | HEART | true | true | Two operational configured pairs | Attempt in stored order; each once; exact identities; maxAge=0 | Covered: [test][test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder] |
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

[test_givenCacheInactiveDisabled_whenExecuted_thenFailureAndNoCalls]: execute.t.sol#L208
[test_givenConfiguredPairBecomesUnsupported_attemptsNextPairWithoutReverting]: execute.t.sol#L130
[test_givenDisabled_isNoOp]: execute.t.sol#L32
[test_givenDisabled_whenUnauthorizedCallerExecutes_reverts]: execute.t.sol#L237
[test_givenEmptyPairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L266
[test_givenEmptyStatusError_whenExecuted_thenZeroSelector]: execute.t.sol#L249
[test_givenFirstPairReverts_attemptsSecondPair]: execute.t.sol#L109
[test_givenInactive_whenExecuted_reverts]: execute.t.sol#L194
[test_givenLargePairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L276
[test_givenLargeStatusError_whenExecuted_thenPrefixOnly]: execute.t.sol#L261
[test_givenOperationalPriceCache_attemptsConfiguredPairsInOrder]: execute.t.sol#L92
[test_givenPriceCacheEnabledQueryReverts_emitsFailureAndReturns]: execute.t.sol#L77
[test_givenPriceCacheIsDisabled_reportsFailure]: execute.t.sol#L62
[test_givenPriceCacheIsInactive_reportsFailure]: execute.t.sol#L46
[test_givenReEnabled_whenExecuted_thenNormalWork]: execute.t.sol#L219
[test_givenReactivated_whenExecuted_thenNormalWork]: execute.t.sol#L228
[test_givenSecondPairReverts_preservesFirstPair]: execute.t.sol#L151
[test_givenShortPairError_whenExecuted_thenNextPairSucceeds]: execute.t.sol#L271
[test_givenShortStatusErrors_whenExecuted_thenPaddedSelectors]: execute.t.sol#L254
[test_whenCallerDoesNotHaveHeartRole_reverts]: execute.t.sol#L21
[test_whenEmptyPairSet_thenNoCacheCalls]: execute.t.sol#L179
[test_whenHeartAndCollectionVary_thenExactAttempts]: execute.t.sol#L169
[test_whenLargerPairSet_thenAllCacheCalls]: execute.t.sol#L189
[test_whenSinglePair_thenOneCacheCall]: execute.t.sol#L184

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-EXECUTE-L04 | Any address, fuzz, without authorization exclusions | false | false | Task paused, then Kernel-deactivated; existing cache/pair fixture retained; No arguments; activity precedes Heart-role check and disabled no-op | `PriceCacherTask_PolicyInactive(task)` before caller, input and dependency checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst]: ./execute.t.sol#L321

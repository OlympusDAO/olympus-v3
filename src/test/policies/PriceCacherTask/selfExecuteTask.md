# PriceCacherTask.selfExecuteTask coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-SELF-EXECUTE`.

The sole direct caller is address(this); external HEART authority alone is insufficient.
The outer execute entry owns scheduler authorization and local pause handling. This body
checks current cache readiness and catches ordinary pair failures independently.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SELF-EXECUTE-A01 | Fuzz non-self callers | true | true | Caller differs from task itself, including HEART/admin/zero | PriceCacherTask_OnlySelf() | Covered: [test][test_whenCallerIsNotSelf_selfExecuteTaskReverts], [test][test_whenCallerBoundarySeedsUsed_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SELF-EXECUTE-D01 | Task itself | true | true | Cache inactive; independently enabled/disabled | PolicyDependency_NotActive(cache); no cache calls | Covered: [test][test_givenCacheInactive_whenCalled_thenDependencyErrorBeforeStatusRead] |
| PCACHER-SELF-EXECUTE-D02 | Task itself | true | true | Cache active but paused | PolicyDependency_NotActive(cache); no cache calls | Covered: [test][test_givenCachePaused_whenCalled_thenDependencyError] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SELF-EXECUTE-N01 | Task itself | true | true | Empty/single/larger pair sets | No work or exactly one call per stored pair | Covered: [test][test_whenCollectionVaries_thenExactAttempts], [test][test_whenEmptyCollection_thenNoAttempts], [test][test_whenSinglePair_thenOneAttempt], [test][test_whenLargerCollection_thenEveryPairAttempted] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SELF-EXECUTE-P01 | Task itself | true | true | Operational cache and configured pairs | Forward each pair with maxAge=0 in order | Covered: [test][test_whenCollectionVaries_thenExactAttempts], [test][test_whenEmptyCollection_thenNoAttempts], [test][test_whenSinglePair_thenOneAttempt], [test][test_whenLargerCollection_thenEveryPairAttempted] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SELF-EXECUTE-T01 | Task itself | true | true | Status getter reverts | Revert exact dependency error to outer self-call boundary | Covered: [test][test_givenStatusGetterReverts_whenCalled_reverts] |
| PCACHER-SELF-EXECUTE-T02 | Task itself | true | true | One pair fails; another succeeds | Catch pair error, emit exact event and retain independent success | Covered: [test][test_givenFirstPairFails_whenCalled_thenSecondPairSucceeds] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenCacheInactive_whenCalled_thenDependencyErrorBeforeStatusRead]: selfExecuteTask.t.sol#L33
[test_givenCachePaused_whenCalled_thenDependencyError]: selfExecuteTask.t.sol#L55
[test_givenFirstPairFails_whenCalled_thenSecondPairSucceeds]: selfExecuteTask.t.sol#L107
[test_givenStatusGetterReverts_whenCalled_reverts]: selfExecuteTask.t.sol#L93
[test_whenCallerBoundarySeedsUsed_reverts]: selfExecuteTask.t.sol#L26
[test_whenCallerIsNotSelf_selfExecuteTaskReverts]: selfExecuteTask.t.sol#L16
[test_whenCollectionVaries_thenExactAttempts]: selfExecuteTask.t.sol#L69
[test_whenEmptyCollection_thenNoAttempts]: selfExecuteTask.t.sol#L78
[test_whenLargerCollection_thenEveryPairAttempted]: selfExecuteTask.t.sol#L88
[test_whenSinglePair_thenOneAttempt]: selfExecuteTask.t.sol#L83

# PriceCacherTask.setPriceCache coverage plan

Coverage records implemented domains and assertions independently of test pass/fail status.

Source: [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope: `PCACHER-SET-CACHE`.

ADMIN selects a cache while enabled or paused. Compatibility requires IPriceCache and IEnabler,
a canonical matching Kernel and support for each stored pair.
priceCache() is the corresponding permissionless getter. Activation independently requires
readiness; selection performs compatibility and pair-support checks only.
Selecting the current cache reverts before candidate probes.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

Cache compatibility is defined by the consumed interfaces and Kernel binding.
The task must neither require IVersioned support nor call the cache VERSION getter.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-A01 | Fuzz unauthorized callers | true | true | Fuzz callers excluding every ADMIN | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenCallerIsNotAdmin_reverts] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-L01 | ADMIN | true | false | Rotate while paused | Store replacement without enabling task | Covered: [test][test_givenDisabled_whenAdminRotatesPriceCache] |
| PCACHER-SET-CACHE-L02 | ADMIN | false | Fuzz true/false | Task Kernel-inactive | PriceCacherTask_PolicyInactive(subject); unchanged | Covered: [test][test_givenInactive_whenCacheSelected_reverts] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-I01 | ADMIN | true | true | Candidate=0 | PriceCacherTask_ZeroAddress(); old pointer retained | Covered: [test][test_whenCandidateIsZero_revertsAndPreservesCache] |
| PCACHER-SET-CACHE-I02 | ADMIN | true | true | Candidate equals stored cache | PriceCacherTask_UnchangedAddress(current), before probes/events; unchanged | Covered: [test][test_whenUnchangedCacheSelected_revertsBeforeProbes] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-D02 | ADMIN | true | true | Foreign Kernel | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel); old pointer retained | Covered: [test][test_whenCandidateUsesDifferentKernel_revertsAndPreservesCache] |
| PCACHER-SET-CACHE-D03 | ADMIN | true | true | Candidate rejects one stored pair | Propagate PairUnsupported(asset,quote); old pointer retained | Covered: [test][test_whenCandidateDoesNotSupportAnExistingPair_revertsAndPreservesCache], [test][test_givenLaterPairRejected_whenSelected_thenAtomicRollback] |
| PCACHER-SET-CACHE-D04 | ADMIN | true | true | Candidate is a non-contract address | PriceCacherTask_InvalidPriceCache(candidate); unchanged | Covered: [test][test_whenCandidateHasNoCode_reverts] |
| PCACHER-SET-CACHE-D05 | ADMIN | true | true | Compatible candidate VERSION getter reverts | Accept; do not query VERSION; exact pointer/event; preserve pairs and lifecycle | Covered: [test][test_givenVersionGetterReverts_whenSelected_thenIgnored] |
| PCACHER-SET-CACHE-D06 | ADMIN | true | true | Compatible paused/inactive candidate | Compatibility-only selection; subsequent activation rejects unready cache | Covered: [test][test_givenUnreadyCandidate_whenSelected_thenActivationRejects] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-N01 | ADMIN | true | true | Zero, one and multiple configured pairs; seed 0,1,32 fixture entries | Validate every pair atomically; preserve old pointer on later failure | Covered: [test][test_whenAdminAndCollectionVary_thenExactRotation], [test][test_whenNoPairs_whenRotationSucceeds], [test][test_whenSinglePair_whenRotationSucceeds], [test][test_whenLargerSet_whenRotationSucceeds], [test][test_givenLaterPairRejected_whenSelected_thenAtomicRollback] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-P01 | ADMIN | true | true | Compatible active/enabled replacement | Exact PriceCacheSet event/getter; subsequent execute uses new cache only | Covered: [test][test_givenEnabled_whenAdminRotatesPriceCache], [test][test_whenAdminAndCollectionVary_thenExactRotation] |
| PCACHER-SET-CACHE-P02 | Fuzz all callers | Fuzz true/false | Fuzz true/false | Any getter caller; all local lifecycle states | Return currently selected cache without writes | Covered: [test][test_whenAnyCallerReadsCache] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-D07 | ADMIN | true | true | IPriceCache interface missing | PriceCacherTask_InvalidPriceCache(candidate); old binding unchanged | Covered: [test][test_givenCacheInterfaceMissing_whenSelected_reverts] |
| PCACHER-SET-CACHE-D08 | ADMIN | true | true | IEnabler interface missing | PriceCacherTask_InvalidPriceCache(candidate); old binding unchanged | Covered: [test][test_givenEnablerInterfaceMissing_whenSelected_reverts] |
| PCACHER-SET-CACHE-D09 | ADMIN | true | true | Compatible candidate omits IVersioned | Accept; do not query VERSION; exact pointer/event; preserve pairs and lifecycle | Covered: [test][test_givenNoVersionInterface_whenSelected_thenAccepted] |
| PCACHER-SET-CACHE-D11 | ADMIN | true | true | kernel() getter reverts | PolicyDependency_InvalidDependency(candidate); old binding unchanged | Covered: [test][test_givenKernelGetterReverts_whenSelected_reverts] |
| PCACHER-SET-CACHE-D12 | ADMIN | true | true | kernel() response malformed | PolicyDependency_InvalidDependency(candidate); old binding unchanged | Covered: [test][test_givenMalformedKernel_whenSelected_reverts], [test][test_givenNoncanonicalKernel_whenSelected_reverts], [test][test_whenMetadataBoundarySeedsUsed_reverts] |

## Additional authorization and boundary cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-A02 | Fuzz every ADMIN holder | true | true | Compatible replacement; zero/one/larger pair sets | Exact event and pointer; preserve pair order and lifecycle; only replacement receives subsequent work | Covered: [test][test_whenAdminAndCollectionVary_thenExactRotation] |
| PCACHER-SET-CACHE-D13 | ADMIN | true | true | ERC165 probe reverts | PriceCacherTask_InvalidPriceCache(candidate); unchanged | Covered: [test][test_givenInterfaceProbeReverts_whenSelected_reverts] |
| PCACHER-SET-CACHE-D14 | ADMIN | true | true | ERC165 probe returns malformed bool ABI | PriceCacherTask_InvalidPriceCache(candidate); unchanged | Covered: [test][test_givenInterfaceProbeMalformed_whenSelected_reverts] |

[test_givenCacheInterfaceMissing_whenSelected_reverts]: setPriceCache.t.sol#L207
[test_givenDisabled_whenAdminRotatesPriceCache]: setPriceCache.t.sol#L53
[test_givenEnabled_whenAdminRotatesPriceCache]: setPriceCache.t.sol#L32
[test_givenEnablerInterfaceMissing_whenSelected_reverts]: setPriceCache.t.sol#L212
[test_givenInactive_whenCacheSelected_reverts]: setPriceCache.t.sol#L154
[test_givenInterfaceProbeMalformed_whenSelected_reverts]: setPriceCache.t.sol#L306
[test_givenInterfaceProbeReverts_whenSelected_reverts]: setPriceCache.t.sol#L295
[test_givenKernelGetterReverts_whenSelected_reverts]: setPriceCache.t.sol#L217
[test_givenLaterPairRejected_whenSelected_thenAtomicRollback]: setPriceCache.t.sol#L317
[test_givenMalformedKernel_whenSelected_reverts]: setPriceCache.t.sol#L230
[test_givenNoVersionInterface_whenSelected_thenAccepted]: setPriceCache.t.sol#L352
[test_givenNoncanonicalKernel_whenSelected_reverts]: setPriceCache.t.sol#L236
[test_givenUnreadyCandidate_whenSelected_thenActivationRejects]: setPriceCache.t.sol#L186
[test_givenVersionGetterReverts_whenSelected_thenIgnored]: setPriceCache.t.sol#L360
[test_whenAdminAndCollectionVary_thenExactRotation]: setPriceCache.t.sol#L117
[test_whenAnyCallerReadsCache]: setPriceCache.t.sol#L242
[test_whenCallerIsNotAdmin_reverts]: setPriceCache.t.sol#L21
[test_whenCandidateDoesNotSupportAnExistingPair_revertsAndPreservesCache]: setPriceCache.t.sol#L96
[test_whenCandidateHasNoCode_reverts]: setPriceCache.t.sol#L180
[test_whenCandidateIsZero_revertsAndPreservesCache]: setPriceCache.t.sol#L64
[test_whenCandidateUsesDifferentKernel_revertsAndPreservesCache]: setPriceCache.t.sol#L75
[test_whenLargerSet_whenRotationSucceeds]: setPriceCache.t.sol#L149
[test_whenMetadataBoundarySeedsUsed_reverts]: setPriceCache.t.sol#L342
[test_whenNoPairs_whenRotationSucceeds]: setPriceCache.t.sol#L139
[test_whenSinglePair_whenRotationSucceeds]: setPriceCache.t.sol#L144
[test_whenUnchangedCacheSelected_revertsBeforeProbes]: setPriceCache.t.sol#L168

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PCACHER-SET-CACHE-L03 | Any address, fuzz, without authorization exclusions | false | false | Task paused, then Kernel-deactivated; existing cache/pair fixture retained; Candidate=`address(0)` | `PriceCacherTask_PolicyInactive(task)` before caller, input and dependency checks | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenUnauthorizedCaller_revertsActivityFirst]: ./setPriceCache.t.sol#L367

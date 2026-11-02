# PriceCache.getCachedPrice coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-GET-CACHED`.

Permissionless active/enabled view. It validates pair support and decimals each time,
then returns stored oriented USD legs, observation timestamp and round ID without a live
price read. Missing/invalidated snapshots are all-zero; staleness alone does not zero a
snapshot. Module/metadata invalidation proofs map with their mutating configure/set actions.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GET-CACHED-L01 | Any caller | true | false | Paused policy | NotEnabled() | Covered: [test][test_whenPolicyDisabled_reverts] |
| PCACHE-GET-CACHED-L02 | Any caller | false | true | Inactive policy | PriceCache_PolicyNotActive() | Covered: [test][test_whenPolicyIsDeactivated_reverts] |
| PCACHE-GET-CACHED-L03 | Fuzz all callers | false | false | Policy inactive and disabled | PriceCache_PolicyNotActive() before local disablement | Covered: [test][test_givenInactivePaused_whenCalled_reverts] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GET-CACHED-I01 | Any caller | true | true | Asset removed from PRICE after caching | PRICE_AssetNotApproved(asset) | Covered: [test][test_whenAssetRemovedFromPRICE_reverts] |
| PCACHE-GET-CACHED-I02 | Any caller | true | true | Quote removed after caching | PRICE_AssetNotApproved(quote) | Covered: [test][test_whenQuoteRemovedFromPRICE_reverts] |
| PCACHE-GET-CACHED-I03 | Fuzz all callers | true | true | Asset=0 | PriceCache_InvalidPair(0,quote) | Covered: [test][test_whenAssetZero_reverts] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GET-CACHED-P01 | Any caller | true | true | Cached pair in both orientations | Exact USD legs reversed; shared round and timestamp | Covered: [test][test_givenPairIsCached_getCachedPrice_returnsSeparateUsdLegs] |
| PCACHE-GET-CACHED-P02 | Fuzz all callers | true | true | No snapshot for otherwise valid pair | Return four zero fields without live PRICE price read | Covered: [test][test_whenUncachedPairReadAvoidsLivePrice] |
| PCACHE-GET-CACHED-P03 | Fuzz all callers | true | true | Stale but non-invalidated snapshot | Return stored stale values unchanged | Covered: [test][test_whenStaleSnapshotRemainsReadable] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GET-CACHED-L04 | Fuzz all callers | true | true | Policy restored through reEnable or Kernel reactivation | Normal read succeeds with exact stored snapshot | Covered: [test][test_givenReEnabled_whenCalled], [test][test_givenReactivated_whenCalled] |

## Missing metadata

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-GET-CACHED-I04 | Fuzz all callers | true | true | Quote=0 | PriceCache_InvalidPair(asset,0) | Covered: [test][test_whenQuoteZero_reverts] |
| PCACHE-GET-CACHED-I05 | Fuzz all callers | true | true | Asset equals quote | PriceCache_InvalidPair(asset,asset) | Covered: [test][test_whenSamePair_reverts] |
| PCACHE-GET-CACHED-I06 | Fuzz all callers | true | true | Approved non-contract asset lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_whenAssetMetadataMissing_reverts] |
| PCACHE-GET-CACHED-I07 | Fuzz all callers | true | true | Approved non-contract quote lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(quote) | Covered: [test][test_whenQuoteMetadataMissing_reverts] |

[test_whenPolicyDisabled_reverts]: getCachedPrice.t.sol#L15
[test_whenPolicyIsDeactivated_reverts]: getCachedPrice.t.sol#L159
[test_givenInactivePaused_whenCalled_reverts]: getCachedPrice.t.sol#L238
[test_whenAssetRemovedFromPRICE_reverts]: getCachedPrice.t.sol#L66
[test_whenQuoteRemovedFromPRICE_reverts]: getCachedPrice.t.sol#L79
[test_whenAssetZero_reverts]: getCachedPrice.t.sol#L169
[test_givenPairIsCached_getCachedPrice_returnsSeparateUsdLegs]: getCachedPrice.t.sol#L26
[test_whenUncachedPairReadAvoidsLivePrice]: getCachedPrice.t.sol#L273
[test_whenStaleSnapshotRemainsReadable]: getCachedPrice.t.sol#L289
[test_givenReEnabled_whenCalled]: getCachedPrice.t.sol#L247
[test_givenReactivated_whenCalled]: getCachedPrice.t.sol#L260
[test_whenQuoteZero_reverts]: getCachedPrice.t.sol#L182
[test_whenSamePair_reverts]: getCachedPrice.t.sol#L195
[test_whenAssetMetadataMissing_reverts]: getCachedPrice.t.sol#L208
[test_whenQuoteMetadataMissing_reverts]: getCachedPrice.t.sol#L223

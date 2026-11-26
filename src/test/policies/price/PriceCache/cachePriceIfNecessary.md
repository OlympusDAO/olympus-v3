# PriceCache.cachePriceIfNecessary coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-CACHE-IF-NECESSARY`.

This is permissionless. Own Kernel activity is checked before local enablement, then pair
validity and metadata. Prices are separate PRICE/USD uint256 legs in PRICE.decimals units;
no division or ratio rounding occurs here. Both orientations share a single snapshot and
uint80 round ID. Unit legs use 10**PRICE.decimals and current block time. Current-price
lookup/validation belongs to PRICE. Getter returns must match the stored oriented snapshot.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-L01 | Any caller | true | false | Paused policy | NotEnabled() | Covered: [test][test_whenPolicyDisabled_reverts] |
| PCACHE-CACHE-IF-NECESSARY-L02 | Any caller | false | true | Kernel-inactive policy | PriceCache_PolicyNotActive() | Covered: [test][test_whenPolicyIsDeactivated_reverts] |
| PCACHE-CACHE-IF-NECESSARY-L03 | Fuzz all callers | false | false | Both inactive and disabled | PriceCache_PolicyNotActive before local disablement or input checks | Covered: [test][test_givenInactivePaused_whenCalled_reverts] |
| PCACHE-CACHE-IF-NECESSARY-L04 | Fuzz all callers | true | true | After reEnable or Kernel reactivation | Normal cache behavior resumes | Covered: [test][test_givenReEnabled_whenCalled], [test][test_givenReactivated_whenCalled] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-I01 | Any caller | true | true | Asset=0 | PriceCache_InvalidPair(0,quote) | Covered: [test][test_whenAssetZero_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-D01 | Any caller | true | true | Fresh snapshot but PRICE current-price call fails | Fresh-hit path must not read current prices | Covered: [test][test_whenFreshHitAvoidsLivePrice] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-N01 | Any caller | true | true | Snapshot exactly maxAge old | Inclusive freshness; return existing snapshot | Covered: [test][test_givenSnapshotIsExactlyMaxAgeOld_returnsExistingSnapshot] |
| PCACHE-CACHE-IF-NECESSARY-N02 | Any caller | true | true | maxAge=0 in same observation block | Return existing snapshot | Covered: [test][test_givenSnapshotIsCurrent_whenMaxAgeIsZero_returnsExistingSnapshot] |
| PCACHE-CACHE-IF-NECESSARY-N03 | Any caller | true | true | maxAge=MAX48 | Return existing snapshot | Covered: [test][test_givenSnapshotExists_whenMaxAgeIsMaximum_returnsExistingSnapshot] |
| PCACHE-CACHE-IF-NECESSARY-N04 | Fuzz all callers | true | true | Fuzz maxAge 0..MAX48 and independent now/time; seed 1 and first-stale instant | Recache iff updatedAt=0 or now>updatedAt+maxAge; widened deadline arithmetic | Covered: [test][test_whenFullRangeFreshnessHolds], [test][test_whenFullRangeSnapshotIsFirstStale], [test][test_whenAgeOneAtAndAfterDeadline] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-P01 | Fuzz all callers | true | true | No snapshot exists | Cache once and return exact stored snapshot | Covered: [test][test_whenNoSnapshotExists_cachesPair] |
| PCACHE-CACHE-IF-NECESSARY-P02 | Any caller | true | true | Fresh snapshot | No recache; exact stored fields/round/time unchanged | Covered: [test][test_whenSnapshotIsFresh_doesNotRecache] |
| PCACHE-CACHE-IF-NECESSARY-P03 | Any caller | true | true | Fresh reverse request | Return same pair with reversed legs | Covered: [test][test_givenSnapshotIsFresh_whenPairIsReversed_returnsExistingSnapshot] |
| PCACHE-CACHE-IF-NECESSARY-P04 | Any caller | true | true | Stale snapshot | Recache; increment round; return exact new storage | Covered: [test][test_whenSnapshotIsStale_recachesPair] |
| PCACHE-CACHE-IF-NECESSARY-P05 | Any caller | true | true | PRICE module replaced | Invalidated pair recaches into new epoch, round restarts at 1 | Covered: [test][test_whenPRICEModuleIsUpgraded_invalidatedPairRecachesOnDemand] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-T01 | Any caller | true | true | Stale snapshot and PRICE fails | Exact PRICE_PriceZero(asset); preserve old snapshot | Covered: [test][test_givenSnapshotIsStale_whenPRICEReverts_revertsAndPreservesSnapshot] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-IF-NECESSARY-I02 | Fuzz all callers | true | true | Quote=0 | PriceCache_InvalidPair(asset,0) | Covered: [test][test_whenQuoteZero_reverts] |
| PCACHE-CACHE-IF-NECESSARY-I03 | Fuzz all callers | true | true | Asset equals quote | PriceCache_InvalidPair(asset,asset) | Covered: [test][test_whenSamePair_reverts] |
| PCACHE-CACHE-IF-NECESSARY-I04 | Fuzz all callers | true | true | Asset unapproved | PRICE_AssetNotApproved(asset) | Covered: [test][test_whenAssetUnapproved_reverts] |
| PCACHE-CACHE-IF-NECESSARY-I05 | Fuzz all callers | true | true | Quote unapproved | PRICE_AssetNotApproved(quote) | Covered: [test][test_whenQuoteUnapproved_reverts] |
| PCACHE-CACHE-IF-NECESSARY-I06 | Fuzz all callers | true | true | Approved non-contract asset lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_whenAssetMetadataMissing_reverts] |
| PCACHE-CACHE-IF-NECESSARY-I07 | Fuzz all callers | true | true | Approved non-contract quote lacks metadata | PriceCache_NonContractAssetDecimalsNotRegistered(quote) | Covered: [test][test_whenQuoteMetadataMissing_reverts] |

[test_whenPolicyDisabled_reverts]: cachePriceIfNecessary.t.sol#L25
[test_whenPolicyIsDeactivated_reverts]: cachePriceIfNecessary.t.sol#L36
[test_givenInactivePaused_whenCalled_reverts]: cachePriceIfNecessary.t.sol#L310
[test_givenReEnabled_whenCalled]: cachePriceIfNecessary.t.sol#L319
[test_givenReactivated_whenCalled]: cachePriceIfNecessary.t.sol#L332
[test_whenAssetZero_reverts]: cachePriceIfNecessary.t.sol#L223
[test_whenFreshHitAvoidsLivePrice]: cachePriceIfNecessary.t.sol#L345
[test_givenSnapshotIsExactlyMaxAgeOld_returnsExistingSnapshot]: cachePriceIfNecessary.t.sol#L110
[test_givenSnapshotIsCurrent_whenMaxAgeIsZero_returnsExistingSnapshot]: cachePriceIfNecessary.t.sol#L128
[test_givenSnapshotExists_whenMaxAgeIsMaximum_returnsExistingSnapshot]: cachePriceIfNecessary.t.sol#L145
[test_whenFullRangeFreshnessHolds]: cachePriceIfNecessary.t.sol#L360
[test_whenFullRangeSnapshotIsFirstStale]: cachePriceIfNecessary.t.sol#L379
[test_whenAgeOneAtAndAfterDeadline]: cachePriceIfNecessary.t.sol#L396
[test_whenNoSnapshotExists_cachesPair]: cachePriceIfNecessary.t.sol#L48
[test_whenSnapshotIsFresh_doesNotRecache]: cachePriceIfNecessary.t.sol#L65
[test_givenSnapshotIsFresh_whenPairIsReversed_returnsExistingSnapshot]: cachePriceIfNecessary.t.sol#L88
[test_whenSnapshotIsStale_recachesPair]: cachePriceIfNecessary.t.sol#L159
[test_whenPRICEModuleIsUpgraded_invalidatedPairRecachesOnDemand]: cachePriceIfNecessary.t.sol#L200
[test_givenSnapshotIsStale_whenPRICEReverts_revertsAndPreservesSnapshot]: cachePriceIfNecessary.t.sol#L182
[test_whenQuoteZero_reverts]: cachePriceIfNecessary.t.sol#L236
[test_whenSamePair_reverts]: cachePriceIfNecessary.t.sol#L249
[test_whenAssetUnapproved_reverts]: cachePriceIfNecessary.t.sol#L262
[test_whenQuoteUnapproved_reverts]: cachePriceIfNecessary.t.sol#L271
[test_whenAssetMetadataMissing_reverts]: cachePriceIfNecessary.t.sol#L280
[test_whenQuoteMetadataMissing_reverts]: cachePriceIfNecessary.t.sol#L295

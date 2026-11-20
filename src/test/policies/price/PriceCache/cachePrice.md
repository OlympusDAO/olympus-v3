# PriceCache.cachePrice coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-CACHE`.

This is permissionless. Own Kernel activity is checked before local enablement, then pair
validity and metadata. Prices are separate PRICE/USD uint256 legs in PRICE.decimals units;
no division or ratio rounding occurs here. Both orientations share a single snapshot and
uint80 round ID. Unit legs use 10**PRICE.decimals and current block time. Current-price
lookup/validation belongs to PRICE. Getter returns must match the stored oriented snapshot.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-A01 | Fuzz all callers | true | true | Fuzz all caller identities with valid pair | Identical authoritative snapshot regardless of caller | Covered: [test][test_whenAnyCallerCachesValidPair] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-L01 | Any caller | true | false | Paused policy | NotEnabled() | Covered: [test][test_whenPolicyDisabled_reverts] |
| PCACHE-CACHE-L02 | Any caller | false | true | Kernel-inactive policy | PriceCache_PolicyNotActive() | Covered: [test][test_whenPolicyIsDeactivated_reverts] |
| PCACHE-CACHE-L03 | Fuzz all callers | false | false | Both inactive and disabled | PriceCache_PolicyNotActive before local disablement or input checks | Covered: [test][test_givenInactivePaused_whenCalled_reverts] |
| PCACHE-CACHE-L04 | Fuzz all callers | true | true | After reEnable or Kernel reactivation | Normal cache behavior resumes | Covered: [test][test_givenReEnabled_whenCalled], [test][test_givenReactivated_whenCalled] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-I01 | Any caller | true | true | Asset=0 | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenAssetIsZeroAddress_reverts] |
| PCACHE-CACHE-I02 | Any caller | true | true | Quote=0 | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenQuoteIsZeroAddress_reverts] |
| PCACHE-CACHE-I03 | Any caller | true | true | Identical pair | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenAssetAndQuoteAreSame_reverts] |
| PCACHE-CACHE-I04 | Any caller | true | true | Asset unapproved | PRICE_AssetNotApproved(asset) | Covered: [test][test_whenAssetIsUnapproved_reverts] |
| PCACHE-CACHE-I05 | Any caller | true | true | Quote unapproved | PRICE_AssetNotApproved(quote) | Covered: [test][test_whenQuoteIsUnapproved_reverts] |
| PCACHE-CACHE-I06 | Any caller | true | true | Both unapproved | Asset approval error first | Covered: [test][test_whenBothAssetsAreUnapproved_reverts] |

## Dependencies

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-D01 | Any caller | true | true | PRICE leg getter reverts MetadataReadFailed() | Propagate exact MetadataReadFailed(); preserve previous snapshot | Covered: [test][test_whenPriceReadFails_preservesSnapshot] |
| PCACHE-CACHE-D02 | Any caller | true | true | Approved non-contract leg lacks decimals metadata | PriceCache_NonContractAssetDecimalsNotRegistered(asset); no snapshot written | Covered: [test][test_whenRequiredDecimalsAreMissing_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-N01 | Any caller | true | true | Independent leg observation timestamps, including older quote | updatedAt=min(asset timestamp,quote timestamp); price units unchanged | Covered: [test][test_whenObservationTimesVaryIndependently] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-CACHE-P01 | Any caller | true | true | Valid uncached pair followed by another write | Exact USD legs; round 1 then 2; timestamp advances | Covered: [test][test_whenPairIsValid_cachesSnapshotAndIncrementsRoundId] |
| PCACHE-CACHE-P02 | Any caller | true | true | Repeated forward/reverse writes | Shared round and timestamp; correctly oriented legs | Covered: [test][test_whenCachedMultipleTimes_updatesRoundTimestampAndBothDirections] |
| PCACHE-CACHE-P03 | Any caller | true | true | Unit as asset | Unit leg=10**PRICE.decimals; exact quote leg | Covered: [test][test_whenAssetIsUnitOfAccount_cachesUnitPriceAsAssetLeg] |
| PCACHE-CACHE-P04 | Any caller | true | true | Unit as quote | Exact asset leg and unit quote leg | Covered: [test][test_whenQuoteIsUnitOfAccount_cachesUnitPriceAsQuoteLeg] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_whenAnyCallerCachesValidPair]: cachePrice.t.sol#L279
[test_whenPolicyDisabled_reverts]: cachePrice.t.sol#L17
[test_whenPolicyIsDeactivated_reverts]: cachePrice.t.sol#L26
[test_givenInactivePaused_whenCalled_reverts]: cachePrice.t.sol#L250
[test_givenReEnabled_whenCalled]: cachePrice.t.sol#L259
[test_givenReactivated_whenCalled]: cachePrice.t.sol#L269
[test_whenAssetIsZeroAddress_reverts]: cachePrice.t.sol#L46
[test_whenQuoteIsZeroAddress_reverts]: cachePrice.t.sol#L58
[test_whenAssetAndQuoteAreSame_reverts]: cachePrice.t.sol#L34
[test_whenAssetIsUnapproved_reverts]: cachePrice.t.sol#L70
[test_whenQuoteIsUnapproved_reverts]: cachePrice.t.sol#L78
[test_whenBothAssetsAreUnapproved_reverts]: cachePrice.t.sol#L86
[test_whenPriceReadFails_preservesSnapshot]: cachePrice.t.sol#L309
[test_whenRequiredDecimalsAreMissing_reverts]: cachePrice.t.sol#L323
[test_whenObservationTimesVaryIndependently]: cachePrice.t.sol#L289
[test_whenPairIsValid_cachesSnapshotAndIncrementsRoundId]: cachePrice.t.sol#L96
[test_whenCachedMultipleTimes_updatesRoundTimestampAndBothDirections]: cachePrice.t.sol#L113
[test_whenAssetIsUnitOfAccount_cachesUnitPriceAsAssetLeg]: cachePrice.t.sol#L210
[test_whenQuoteIsUnitOfAccount_cachesUnitPriceAsQuoteLeg]: cachePrice.t.sol#L230

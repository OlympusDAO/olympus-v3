# PriceCache.validateAssetPair coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-VALIDATE-PAIR`.

Validation is permissionless and remains available while disabled/inactive. Order is
nonzero/distinct pair, asset approval, quote approval, then resolvable asset/quote decimals.
A unit-of-account leg is exempt from PRICE approval. It reads no current prices or snapshots.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VALIDATE-PAIR-L01 | Any caller | true | false | Supported pair while paused | Success | Covered: [test][test_givenCacheIsDisabled_whenPairIsSupported] |
| PCACHE-VALIDATE-PAIR-L02 | Any caller | false | true | Supported pair while inactive | Success | Covered: [test][test_givenCacheIsInactive_whenPairIsSupported] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VALIDATE-PAIR-I01 | Any caller | true | true | Asset=0 | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenAssetIsZero_reverts] |
| PCACHE-VALIDATE-PAIR-I02 | Any caller | true | true | Quote=0 | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenQuoteIsZero_reverts] |
| PCACHE-VALIDATE-PAIR-I03 | Any caller | true | true | Asset=quote | PriceCache_InvalidPair(asset,quote) | Covered: [test][test_whenAssetEqualsQuote_reverts] |
| PCACHE-VALIDATE-PAIR-I04 | Any caller | true | true | Asset not approved | PRICE_AssetNotApproved(asset) | Covered: [test][test_whenAssetIsNotApproved_reverts] |
| PCACHE-VALIDATE-PAIR-I05 | Any caller | true | true | Quote not approved | PRICE_AssetNotApproved(quote) | Covered: [test][test_whenQuoteIsNotApproved_reverts] |
| PCACHE-VALIDATE-PAIR-I06 | Any caller | true | true | Approved non-contract asset lacks decimals | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_whenApprovedNonContractAssetHasNoCacheDecimals_reverts] |
| PCACHE-VALIDATE-PAIR-I07 | Any caller | true | true | Asset=0 and quote=0 | PriceCache_InvalidPair(0,0) before module approval calls | Covered: [test][test_whenBothAssetsAreZero_reverts] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VALIDATE-PAIR-P01 | Fuzz all callers | true | true | Supported pair; arbitrary caller | Success without writes | Covered: [test][test_whenCallerIsArbitrary_whenPairIsSupported] |
| PCACHE-VALIDATE-PAIR-P02 | Fuzz all callers | true | true | Unit leg in both orientations; exact metadata types | Success without requiring unit approval | Covered: [test][test_whenUnitIsEitherLeg] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-VALIDATE-PAIR-I08 | Any caller | true | true | Both legs unapproved | PRICE_AssetNotApproved(asset), before quote approval | Covered: [test][test_whenBothAssetsUnapproved_revertsForAsset] |
| PCACHE-VALIDATE-PAIR-I09 | Any caller | true | true | Asset valid, approved quote lacks non-contract decimals | PriceCache_NonContractAssetDecimalsNotRegistered(quote) | Covered: [test][test_whenQuoteMetadataMissing_reverts] |

[test_givenCacheIsDisabled_whenPairIsSupported]: validateAssetPair.t.sol#L94
[test_givenCacheIsInactive_whenPairIsSupported]: validateAssetPair.t.sol#L105
[test_whenAssetIsZero_reverts]: validateAssetPair.t.sol#L15
[test_whenQuoteIsZero_reverts]: validateAssetPair.t.sol#L29
[test_whenAssetEqualsQuote_reverts]: validateAssetPair.t.sol#L43
[test_whenAssetIsNotApproved_reverts]: validateAssetPair.t.sol#L57
[test_whenQuoteIsNotApproved_reverts]: validateAssetPair.t.sol#L67
[test_whenApprovedNonContractAssetHasNoCacheDecimals_reverts]: validateAssetPair.t.sol#L77
[test_whenBothAssetsAreZero_reverts]: validateAssetPair.t.sol#L121
[test_whenCallerIsArbitrary_whenPairIsSupported]: validateAssetPair.t.sol#L115
[test_whenUnitIsEitherLeg]: validateAssetPair.t.sol#L156
[test_whenBothAssetsUnapproved_revertsForAsset]: validateAssetPair.t.sol#L133
[test_whenQuoteMetadataMissing_reverts]: validateAssetPair.t.sol#L142

# PriceCache.setNonContractAssetMetadata coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-METADATA`.

ADMIN or price_admin may set metadata while active and enabled. Decimals span full uint8; symbol
byte length is 1..32. Only known non-contract identifiers and the unit of account qualify.
An actual metadata change increments only that asset invalidation epoch; identical
metadata is a no-op with no writes/events. Cache-read and isStale invalidation assertions
remain in existing getter files but map here to their originating mutation.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-A01 | Fuzz unauthorized callers | true | true | Fuzz callers outside both permitted roles | NotAuthorised() | Covered: [test][test_givenCallerIsNeitherPriceAdminNorAdmin_reverts] |
| PCACHE-METADATA-A02 | Permitted role families | true | true | Fuzz ADMIN-only, price_admin-only and overlap | Accept all permitted classes | Covered: [test][test_givenCallerIsPriceAdmin_updatesConfiguredMetadata], [test][test_givenAdminOnly_whenMetadataSet], [test][test_givenPriceAdminOnly_whenMetadataSet], [test][test_givenBothRoles_whenMetadataSet] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-L01 | ADMIN | true | false | Policy paused | NotEnabled() | Covered: [test][test_givenPolicyDisabled_reverts] |
| PCACHE-METADATA-L02 | ADMIN | false | true | Policy Kernel-inactive | PriceCache_PolicyNotActive(); unchanged | Covered: [test][test_givenInactive_whenMetadataSet_reverts] |
| PCACHE-METADATA-L04 | Fuzz all callers | false | false | Inactive, paused, zero asset and empty symbol | PriceCache_PolicyNotActive() before caller and metadata checks; unchanged | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerChangesMetadata_revertsActivityFirst] |
| PCACHE-METADATA-L03 | ADMIN | true | true | After reEnable or Kernel reactivation | Metadata updates succeed again | Covered: [test][test_givenReEnabled_whenMetadataSet], [test][test_givenReactivated_whenMetadataSet] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-I01 | ADMIN | true | true | Unknown nonzero non-contract asset | PriceCache_InvalidAsset(asset) | Covered: [test][test_givenCallerIsAdmin_givenAssetIsNotRegisteredInPRICE_reverts] |
| PCACHE-METADATA-I02 | ADMIN | true | true | Contract asset | PriceCache_InvalidAsset(asset) | Covered: [test][test_givenCallerIsAdmin_givenAssetIsERC20_reverts] |
| PCACHE-METADATA-I03 | ADMIN | true | true | Symbol empty | PriceCache_InvalidAssetSymbol() | Covered: [test][test_givenCallerIsAdmin_givenSymbolIsEmpty_reverts] |
| PCACHE-METADATA-I04 | ADMIN | true | true | Symbol length 33 | PriceCache_InvalidAssetSymbol() | Covered: [test][test_givenCallerIsAdmin_givenSymbolExceedsMaxLength_reverts] |
| PCACHE-METADATA-I05 | Fuzz all callers | true | false | Asset=0 and empty symbol | NotEnabled() before role and field validation | Covered: [test][test_givenPaused_whenInvalidMetadataSet_reverts] |
| PCACHE-METADATA-I07 | Fuzz unauthorized callers | true | true | Asset=0 and empty symbol | NotAuthorised() before field validation | Covered: [test][test_givenUnauthorised_whenInvalidMetadataSet_reverts] |
| PCACHE-METADATA-I08 | ADMIN | false | true | Asset=0 and empty symbol | PriceCache_PolicyNotActive() before field validation | Covered: [test][test_givenInactive_whenInvalidMetadataSet_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-N01 | ADMIN | true | true | Decimals full 0..MAX8, seed 0,1,MAX8; symbol lengths 1,32 | Exact metadata round trip; invalidate affected pairs | Covered: [test][test_whenMetadataCoversFullDecimalsRange], [test][test_whenDecimalsZero_whenSymbolOneByte], [test][test_whenDecimalsOne_whenSymbolThirtyTwoBytes], [test][test_whenDecimalsMaximum_whenSymbolContainsNulls] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-P01 | ADMIN | true | true | ADMIN updates unit metadata | Exact decimals and symbol getters | Covered: [test][test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_updatesConfiguredMetadata] |
| PCACHE-METADATA-P02 | ADMIN | true | true | ADMIN registers known non-contract asset | Exact metadata getters | Covered: [test][test_givenCallerIsAdmin_givenAssetIsRegisteredNonContractAsset_setsConfiguredMetadata] |
| PCACHE-METADATA-P03 | ADMIN | true | true | Both fields identical to stored metadata | No writes/events or pair invalidation | Covered: [test][test_whenMetadataUnchanged_preservesSnapshotWithoutWritesOrLogs] |
| PCACHE-METADATA-P04 | ADMIN | true | true | Unit metadata changes | Invalidate forward and reverse cached pair fields to zero | Covered: [test][test_whenUnitOfAccountDecimalsChange_invalidatesPairsInBothOrientations] |
| PCACHE-METADATA-P05 | ADMIN | true | true | Non-contract asset decimals change | Invalidate affected pair both ways | Covered: [test][test_whenRegisteredNonContractAssetDecimalsChange_invalidatesPairsInBothOrientations] |
| PCACHE-METADATA-P06 | ADMIN | true | true | Unrelated asset metadata changes | Existing pair retains exact snapshot | Covered: [test][test_whenUnrelatedNonContractAssetDecimalsChange_pairRemainsCached] |
| PCACHE-METADATA-P07 | ADMIN | true | true | Symbol-only change | Invalidate affected pair but preserve unrelated pair | Covered: [test][test_whenOnlySymbolChanged_invalidatesOnlyAffectedPairs] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Staleness consistency after metadata mutation

| ID | Caller | Mutation | Getter result | Test |
| --- | --- | --- | --- | --- |
| PCACHE-METADATA-P08 | ADMIN | Unit metadata changes | isStale true in both orientations | Covered: [test][test_whenUnitOfAccountDecimalsChange_returnsTrueForPairsUsingThatAsset] |
| PCACHE-METADATA-P09 | ADMIN | Registered non-contract asset changes | isStale true in both orientations | Covered: [test][test_whenRegisteredNonContractAssetDecimalsChange_returnsTrueForPairsUsingThatAsset] |
| PCACHE-METADATA-P10 | ADMIN | Unrelated metadata changes | Existing pair remains fresh | Covered: [test][test_whenUnrelatedNonContractAssetDecimalsChange_existingPairRemainsFresh] |

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-METADATA-I06 | ADMIN | true | true | Asset=0 | PriceCache_InvalidAsset(0) | Covered: [test][test_whenAssetZero_reverts] |

## Recache after invalidation

| ID | Caller | Input history | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| PCACHE-METADATA-P11 | Any caller | Metadata changed after a cached pair existed | Freshness lookup recaches; existing stored round increments, unlike a new module epoch which restarts at 1 | Covered: [test][test_givenMetadataChanged_whenRecached_advancesExistingRound] |

[test_givenCallerIsNeitherPriceAdminNorAdmin_reverts]: setNonContractAssetDecimals.t.sol#L31
[test_givenCallerIsPriceAdmin_updatesConfiguredMetadata]: setNonContractAssetDecimals.t.sol#L43
[test_givenAdminOnly_whenMetadataSet]: setNonContractAssetDecimals.t.sol#L158
[test_givenPriceAdminOnly_whenMetadataSet]: setNonContractAssetDecimals.t.sol#L165
[test_givenBothRoles_whenMetadataSet]: setNonContractAssetDecimals.t.sol#L172
[test_givenPolicyDisabled_reverts]: setNonContractAssetDecimals.t.sol#L19
[test_givenInactive_whenMetadataSet_reverts]: setNonContractAssetDecimals.t.sol#L149
[test_givenReEnabled_whenMetadataSet]: setNonContractAssetDecimals.t.sol#L279
[test_givenReactivated_whenMetadataSet]: setNonContractAssetDecimals.t.sol#L284
[test_givenCallerIsAdmin_givenAssetIsNotRegisteredInPRICE_reverts]: setNonContractAssetDecimals.t.sol#L96
[test_givenCallerIsAdmin_givenAssetIsERC20_reverts]: setNonContractAssetDecimals.t.sol#L113
[test_givenCallerIsAdmin_givenSymbolIsEmpty_reverts]: setNonContractAssetDecimals.t.sol#L125
[test_givenCallerIsAdmin_givenSymbolExceedsMaxLength_reverts]: setNonContractAssetDecimals.t.sol#L135
[test_givenPaused_whenInvalidMetadataSet_reverts]: setNonContractAssetDecimals.t.sol#L179
[test_givenUnauthorised_whenInvalidMetadataSet_reverts]: setNonContractAssetDecimals.t.sol#L188
[test_givenInactive_whenInvalidMetadataSet_reverts]: setNonContractAssetDecimals.t.sol#L196
[test_whenMetadataCoversFullDecimalsRange]: setNonContractAssetDecimals.t.sol#L212
[test_whenDecimalsZero_whenSymbolOneByte]: setNonContractAssetDecimals.t.sol#L224
[test_whenDecimalsOne_whenSymbolThirtyTwoBytes]: setNonContractAssetDecimals.t.sol#L229
[test_whenDecimalsMaximum_whenSymbolContainsNulls]: setNonContractAssetDecimals.t.sol#L234
[test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_updatesConfiguredMetadata]: setNonContractAssetDecimals.t.sol#L58
[test_givenCallerIsAdmin_givenAssetIsRegisteredNonContractAsset_setsConfiguredMetadata]: setNonContractAssetDecimals.t.sol#L73
[test_whenMetadataUnchanged_preservesSnapshotWithoutWritesOrLogs]: setNonContractAssetDecimals.t.sol#L239
[test_whenUnitOfAccountDecimalsChange_invalidatesPairsInBothOrientations]: getCachedPrice.t.sol#L92
[test_whenRegisteredNonContractAssetDecimalsChange_invalidatesPairsInBothOrientations]: getCachedPrice.t.sol#L111
[test_whenUnrelatedNonContractAssetDecimalsChange_pairRemainsCached]: getCachedPrice.t.sol#L134
[test_whenOnlySymbolChanged_invalidatesOnlyAffectedPairs]: setNonContractAssetDecimals.t.sol#L256
[test_whenUnitOfAccountDecimalsChange_returnsTrueForPairsUsingThatAsset]: isStale.t.sol#L66
[test_whenRegisteredNonContractAssetDecimalsChange_returnsTrueForPairsUsingThatAsset]: isStale.t.sol#L81
[test_whenUnrelatedNonContractAssetDecimalsChange_existingPairRemainsFresh]: isStale.t.sol#L100
[test_whenAssetZero_reverts]: setNonContractAssetDecimals.t.sol#L203
[test_givenMetadataChanged_whenRecached_advancesExistingRound]: setNonContractAssetDecimals.t.sol#L261

[test_givenInactiveAndDisabled_whenAnyCallerChangesMetadata_revertsActivityFirst]: ./setNonContractAssetDecimals.t.sol#L310

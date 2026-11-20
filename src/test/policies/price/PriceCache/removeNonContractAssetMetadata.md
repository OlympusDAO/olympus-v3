# PriceCache.removeNonContractAssetMetadata coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-REMOVE-METADATA`.

ADMIN or price_admin may remove an existing registry entry while active and enabled. Removing
the unit entry is prohibited. Removal deletes metadata and increments the asset epoch.
A later contract deployment at the same identifier takes precedence for metadata reads.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REMOVE-METADATA-A01 | Fuzz unauthorized callers | true | true | Fuzz callers outside ADMIN/price_admin | NotAuthorised() | Covered: [test][test_givenCallerIsNeitherPriceAdminNorAdmin_reverts] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REMOVE-METADATA-L01 | ADMIN | true | false | Paused policy | NotEnabled() | Covered: [test][test_givenPolicyDisabled_reverts] |
| PCACHE-REMOVE-METADATA-L02 | ADMIN | false | true | Inactive policy | PriceCache_PolicyNotActive(); unchanged | Covered: [test][test_givenInactive_whenMetadataRemoved_reverts] |
| PCACHE-REMOVE-METADATA-L04 | Fuzz all callers | false | false | Inactive, paused and zero asset | PriceCache_PolicyNotActive() before caller and metadata checks; unchanged | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerChangesMetadata_revertsActivityFirst] |
| PCACHE-REMOVE-METADATA-L03 | ADMIN | true | true | After reEnable or Kernel reactivation | Metadata removal succeeds again | Covered: [test][test_givenReEnabled_whenMetadataRemoved], [test][test_givenReactivated_whenMetadataRemoved] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REMOVE-METADATA-I01 | ADMIN | true | true | Unit of account | PriceCache_InvalidAsset(unit) | Covered: [test][test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_reverts] |
| PCACHE-REMOVE-METADATA-I02 | ADMIN | true | true | No existing entry | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_givenCallerIsAdmin_givenAssetDoesNotHaveRegisteredDecimals_reverts] |
| PCACHE-REMOVE-METADATA-I03 | ADMIN | true | true | ERC20 with no registry entry | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_givenCallerIsAdmin_givenAssetIsERC20_reverts] |
| PCACHE-REMOVE-METADATA-I04 | ADMIN | true | true | Repeated removal | PriceCache_NonContractAssetDecimalsNotRegistered(asset); preserve state | Covered: [test][test_givenAlreadyRemoved_whenMetadataRemoved_revertsWithoutWrites] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-REMOVE-METADATA-P01 | Permitted roles | true | true | Registered non-contract asset, ADMIN or price_admin seed | Both metadata getters reject after deletion | Covered: [test][test_givenCallerIsPriceAdminOrAdmin_givenAssetIsRegisteredNonContractAsset_removesConfiguredScale], [test][test_givenAdminOnly_whenMetadataRemoved], [test][test_givenPriceAdminOnly_whenMetadataRemoved], [test][test_givenBothRoles_whenMetadataRemoved] |
| PCACHE-REMOVE-METADATA-P02 | ADMIN | true | true | Code deployed after registry insertion | Remove stale registry; token metadata remains authoritative | Covered: [test][test_givenCallerIsAdmin_givenNcaDecimalsAreRegistered_thenErc20IsDeployed_removesConfiguredScale] |
| PCACHE-REMOVE-METADATA-P03 | ADMIN | true | true | Affected cached pairs plus unrelated pair | Pair reads/cache/staleness revert PriceCache_NonContractAssetDecimalsNotRegistered(asset) until metadata is restored; unrelated pairs preserved | Covered: [test][test_givenMetadataRemoved_whenPairsQueried_revertsUntilRestored] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenCallerIsNeitherPriceAdminNorAdmin_reverts]: removeNonContractAssetDecimals.t.sol#L35
[test_givenPolicyDisabled_reverts]: removeNonContractAssetDecimals.t.sol#L20
[test_givenInactive_whenMetadataRemoved_reverts]: removeNonContractAssetDecimals.t.sol#L148
[test_givenReEnabled_whenMetadataRemoved]: removeNonContractAssetDecimals.t.sol#L244
[test_givenReactivated_whenMetadataRemoved]: removeNonContractAssetDecimals.t.sol#L249
[test_givenCallerIsAdmin_givenAssetIsUnitOfAccount_reverts]: removeNonContractAssetDecimals.t.sol#L83
[test_givenCallerIsAdmin_givenAssetDoesNotHaveRegisteredDecimals_reverts]: removeNonContractAssetDecimals.t.sol#L94
[test_givenCallerIsAdmin_givenAssetIsERC20_reverts]: removeNonContractAssetDecimals.t.sol#L110
[test_givenAlreadyRemoved_whenMetadataRemoved_revertsWithoutWrites]: removeNonContractAssetDecimals.t.sol#L180
[test_givenCallerIsPriceAdminOrAdmin_givenAssetIsRegisteredNonContractAsset_removesConfiguredScale]: removeNonContractAssetDecimals.t.sol#L50
[test_givenAdminOnly_whenMetadataRemoved]: removeNonContractAssetDecimals.t.sol#L159
[test_givenPriceAdminOnly_whenMetadataRemoved]: removeNonContractAssetDecimals.t.sol#L166
[test_givenBothRoles_whenMetadataRemoved]: removeNonContractAssetDecimals.t.sol#L173
[test_givenCallerIsAdmin_givenNcaDecimalsAreRegistered_thenErc20IsDeployed_removesConfiguredScale]: removeNonContractAssetDecimals.t.sol#L122
[test_givenMetadataRemoved_whenPairsQueried_revertsUntilRestored]: removeNonContractAssetDecimals.t.sol#L196

[test_givenInactiveAndDisabled_whenAnyCallerChangesMetadata_revertsActivityFirst]: ./removeNonContractAssetDecimals.t.sol#L280

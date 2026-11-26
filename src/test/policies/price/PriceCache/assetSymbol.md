# PriceCache.assetSymbol coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-ASSET-SYMBOL`.

This permissionless getter does not require local activity or enablement. Contract code
takes precedence over registered non-contract metadata. Non-contract identifiers must
be known to PRICE; the unit of account is always known after dependency configuration.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Authorization

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-A01 | Fuzz all callers | true | true | Fuzz every caller; contract, unit and registered non-contract inputs | Same metadata independent of caller | Covered: [test][test_whenAnyCallerReadsAllMetadataKinds] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-L01 | Fuzz all callers | false | false | Inactive/paused policy, with usable metadata provider | View remains usable | Covered: [test][test_givenInactivePaused_whenMetadataQueried] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-I01 | Any caller | true | true | Registered non-contract asset lacks symbol | PriceCache_NonContractAssetSymbolNotRegistered(asset) | Covered: [test][test_givenAssetIsRegisteredNonContractAsset_givenSymbolIsNotRegistered_reverts] |
| PCACHE-ASSET-SYMBOL-I03 | Any caller | true | true | Asset=0 and unregistered nonzero address | PriceCache_NonContractAssetNotRegistered(asset) | Covered: [test][test_whenAssetIsZero_reverts] |
| PCACHE-ASSET-SYMBOL-I02 | Any caller | true | true | Unknown non-contract asset | PriceCache_NonContractAssetNotRegistered(asset) | Covered: [test][test_whenNonContractAssetIsUnknown_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-N01 | Fuzz all callers | true | true | Empty/one-byte/32-byte token symbols and arbitrary token-return strings | Return exact token-provided bytes; registry length limits apply only to registry writes | Covered: [test][test_whenTokenSymbolHasArbitraryBytes], [test][test_whenTokenSymbolLengthBoundarySeeds] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-P01 | Any caller | true | true | Token contract | Return token symbol | Covered: [test][test_givenAssetIsContract_returnsERC20Symbol] |
| PCACHE-ASSET-SYMBOL-P02 | Any caller | true | true | Unit of account | Return constructor/current registry symbol | Covered: [test][test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredSymbol] |
| PCACHE-ASSET-SYMBOL-P03 | Any caller | true | true | Contract later deployed at registered address | Contract symbol overrides stale registry metadata | Covered: [test][test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractSymbol] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-T01 | Any caller | true | true | Token metadata getter reverts with a stable custom error | Propagate the exact token getter error; no writes | Covered: [test][test_whenTokenMetadataReverts_reverts] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-SYMBOL-T02 | Any caller | true | true | Token metadata response has invalid ABI | Opaque ABI decode revert (0x); no writes | Covered: [test][test_whenTokenMetadataAbiIsMalformed_reverts] |

[test_whenAnyCallerReadsAllMetadataKinds]: assetSymbol.t.sol#L69
[test_givenInactivePaused_whenMetadataQueried]: assetSymbol.t.sol#L79
[test_givenAssetIsRegisteredNonContractAsset_givenSymbolIsNotRegistered_reverts]: assetSymbol.t.sol#L32
[test_whenAssetIsZero_reverts]: assetSymbol.t.sol#L87
[test_whenNonContractAssetIsUnknown_reverts]: assetSymbol.t.sol#L98
[test_whenTokenSymbolHasArbitraryBytes]: assetSymbol.t.sol#L128
[test_whenTokenSymbolLengthBoundarySeeds]: assetSymbol.t.sol#L139
[test_givenAssetIsContract_returnsERC20Symbol]: assetSymbol.t.sol#L14
[test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredSymbol]: assetSymbol.t.sol#L23
[test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractSymbol]: assetSymbol.t.sol#L51
[test_whenTokenMetadataReverts_reverts]: assetSymbol.t.sol#L110
[test_whenTokenMetadataAbiIsMalformed_reverts]: assetSymbol.t.sol#L121

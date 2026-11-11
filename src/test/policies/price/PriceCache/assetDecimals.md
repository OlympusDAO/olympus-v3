# PriceCache.assetDecimals coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-ASSET-DECIMALS`.

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
| PCACHE-ASSET-DECIMALS-A01 | Fuzz all callers | true | true | Fuzz every caller; contract, unit and registered non-contract inputs | Same metadata independent of caller | Covered: [test][test_whenAnyCallerReadsAllMetadataKinds] |

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-L01 | Fuzz all callers | false | false | Inactive/paused policy, with usable metadata provider | View remains usable | Covered: [test][test_givenInactivePaused_whenMetadataQueried] |

## Invalid inputs and precedence

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-I01 | Any caller | true | true | Registered non-contract asset lacks decimals | PriceCache_NonContractAssetDecimalsNotRegistered(asset) | Covered: [test][test_givenAssetIsRegisteredNonContractAsset_givenDecimalsAreNotRegistered_reverts] |
| PCACHE-ASSET-DECIMALS-I02 | Any caller | true | true | Unknown non-contract asset | PriceCache_NonContractAssetNotRegistered(asset) | Covered: [test][test_givenAssetIsUnregisteredNonContractAsset_reverts] |
| PCACHE-ASSET-DECIMALS-I03 | Any caller | true | true | Asset=0 and unregistered nonzero address | PriceCache_NonContractAssetNotRegistered(asset) | Covered: [test][test_whenAssetIsZero_reverts] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-N01 | Fuzz all callers | true | true | Fuzz decimals 0..MAX8; seed 0,1,MAX8 | Return exact uint8 from authoritative provider | Covered: [test][test_whenTokenDecimalsSpanUint8], [test][test_whenTokenDecimalsAtBoundarySeeds] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-P01 | Any caller | true | true | Token contract | Return token decimals | Covered: [test][test_givenAssetIsContract_returnsERC20Decimals] |
| PCACHE-ASSET-DECIMALS-P02 | Any caller | true | true | Unit of account | Return constructor/current registry decimals | Covered: [test][test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredScale] |
| PCACHE-ASSET-DECIMALS-P03 | Any caller | true | true | Contract later deployed at registered address | Contract decimals override stale non-contract metadata | Covered: [test][test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractDecimals] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-T01 | Any caller | true | true | Token metadata getter reverts with a stable custom error | Propagate the exact token getter error; no writes | Covered: [test][test_whenTokenMetadataReverts_reverts] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

## Additional boundary and failure cases

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-ASSET-DECIMALS-T02 | Any caller | true | true | Token metadata response has invalid ABI | Opaque ABI decode revert (0x); no writes | Covered: [test][test_whenTokenMetadataAbiIsMalformed_reverts] |

[test_whenAnyCallerReadsAllMetadataKinds]: assetDecimals.t.sol#L90
[test_givenInactivePaused_whenMetadataQueried]: assetDecimals.t.sol#L100
[test_givenAssetIsRegisteredNonContractAsset_givenDecimalsAreNotRegistered_reverts]: assetDecimals.t.sol#L32
[test_givenAssetIsUnregisteredNonContractAsset_reverts]: assetDecimals.t.sol#L51
[test_whenAssetIsZero_reverts]: assetDecimals.t.sol#L108
[test_whenTokenDecimalsSpanUint8]: assetDecimals.t.sol#L137
[test_whenTokenDecimalsAtBoundarySeeds]: assetDecimals.t.sol#L148
[test_givenAssetIsContract_returnsERC20Decimals]: assetDecimals.t.sol#L14
[test_givenAssetIsUnitOfAccount_returnsConstructorConfiguredScale]: assetDecimals.t.sol#L23
[test_givenAssetIsRegisteredNonContractAsset_givenContractIsLaterDeployedAtTheAddress_returnsContractDecimals]: assetDecimals.t.sol#L66
[test_whenTokenMetadataReverts_reverts]: assetDecimals.t.sol#L119
[test_whenTokenMetadataAbiIsMalformed_reverts]: assetDecimals.t.sol#L130

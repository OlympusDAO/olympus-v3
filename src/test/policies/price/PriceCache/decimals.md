# PriceCache.decimals coverage plan

Source: [PriceCache](../../../../policies/price/PriceCache.sol). Scope: `PCACHE-DECIMALS`.

This permissionless view returns the current PRICE USD-price scale, not the constructor
unit-of-account amount scale. It has no local lifecycle guard and requires a bound PRICE.

Unchanged means relevant bindings, lifecycle, configuration and authoritative state are
preserved; rejected transactions commit no logs. These actions transfer no tokens. A Partial
mapping states the missing proof; Unmapped is an acceptance case awaiting a test. Source gaps
are recorded explicitly and are not converted into passing expectations.

## Lifecycle and membership

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DECIMALS-L01 | Fuzz all callers | false | false | Paused and inactive policy | Read still works with configured PRICE | Covered: [test][test_givenInactivePaused_whenDecimalsQueried] |

## Numeric and collection boundaries

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DECIMALS-N01 | Fuzz all callers | true | true | Fuzz every uint8 module scale; seed 0,1,MAX8 | Exact returned uint8; no normalization | Covered: [test][test_whenPriceScaleSpansUint8], [test][test_whenPriceScaleBoundarySeeds] |

## Successful effects and read consistency

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DECIMALS-P01 | Any caller | true | true | Configured PRICE | Return PRICE.decimals() | Covered: [test][test_returnsPriceModuleUsdScale] |
| PCACHE-DECIMALS-P02 | Any caller | true | true | PRICE scale changes in place | Return new scale immediately | Covered: [test][test_whenPRICEDecimalsChange_returnsUpdatedScale] |
| PCACHE-DECIMALS-P03 | Any caller | true | true | PRICE module replaced | Return newly bound module scale | Covered: [test][test_whenPRICEModuleIsUpgraded_returnsNewModuleScale] |

## External failures

| ID | Caller | Local active | Local enabled | Input or dependency condition | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHE-DECIMALS-T01 | Any caller | true | true | PRICE getter fails or never configured | Propagate reached getter/ABI failure; no state change | Covered: [test][test_whenPriceScaleReadFails_reverts], [test][test_givenUnconfigured_whenDecimalsQueried_reverts] |

- [x] Derive scenarios from concrete entry points and inherited guards.
- [x] Verify named mappings after focused execution.

[test_givenInactivePaused_whenDecimalsQueried]: decimals.t.sol#L36
[test_whenPriceScaleSpansUint8]: decimals.t.sol#L44
[test_whenPriceScaleBoundarySeeds]: decimals.t.sol#L51
[test_returnsPriceModuleUsdScale]: decimals.t.sol#L11
[test_whenPRICEDecimalsChange_returnsUpdatedScale]: decimals.t.sol#L16
[test_whenPRICEModuleIsUpgraded_returnsNewModuleScale]: decimals.t.sol#L26
[test_whenPriceScaleReadFails_reverts]: decimals.t.sol#L58
[test_givenUnconfigured_whenDecimalsQueried_reverts]: decimals.t.sol#L69

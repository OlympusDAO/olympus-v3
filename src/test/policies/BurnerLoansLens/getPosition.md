# BurnerLoansLens.getPosition coverage plan

Source: [getPosition](../../../policies/burnerloans/BurnerLoansLens.sol#L63).

## Domains and notation

Scenario scope: `BLLENS-POSITION`. Lens remains a plain helper, without Kernel membership or IEnabler; SeizerTask owns operational control. Core is its immutable read dependency. All queries are read-only and emit no events. `MAXn=2**n-1`.

Returns `(collateral,principal,maturity,lastBorrowBlock)` from the first canonical FLOAN position for the selected market/borrower. Missing positions produce four zeros. Collateral amounts below have 6 decimals; OHM has 9. T/T2 are distinct valid expiry timestamps; B/B2 are distinct borrow blocks. No Risk or pricing dependency is used.

## Core lifecycle independence

Core activity and local enablement do not gate these read-only queries. Read dependencies otherwise work; fuzz the caller. Lens itself has neither state.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-L01 | Fuzz all callers | true | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveEnabledCore_whenQueried][test_givenActiveEnabledCore_whenQueried] |
| BLLENS-POSITION-L02 | Fuzz all callers | true | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenActiveDisabledCore_whenQueried][test_givenActiveDisabledCore_whenQueried], [test][test_givenDisabledCore_whenLensReads_thenPositionRemainsVisible] |
| BLLENS-POSITION-L03 | Fuzz all callers | false | true | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveEnabledCore_whenQueried][test_givenInactiveEnabledCore_whenQueried] |
| BLLENS-POSITION-L04 | Fuzz all callers | false | false | Same result as the corresponding successful case | No writes or logs | Covered: [test_givenInactiveDisabledCore_whenQueried][test_givenInactiveDisabledCore_whenQueried] |

## Invalid inputs

Borrower may be zero; an unregistered asset is rejected before lookup.

| ID | Caller | Asset | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-I01 | Fuzz all callers | Nonzero unregistered asset | BurnerLoansCore_AssetNotConfigured(asset) | No writes | Covered: [test_whenUnknownAsset_reverts][test_whenUnknownAsset_reverts] |
| BLLENS-POSITION-I02 | Fuzz all callers | Zero asset, unregistered | BurnerLoansCore_AssetNotConfigured(0) | No writes | Covered: [test_whenZeroAsset_reverts][test_whenZeroAsset_reverts] |

## Canonical position states

Use separate fixtures and compare each field to fixed inputs and FLOAN, not another Lens getter.

| ID | Caller | Selected position state | Returned tuple | Test |
| --- | --- | --- | --- | --- |
| BLLENS-POSITION-P02 | Fuzz all callers | Registered asset; borrower has no position | (0,0,0,0) | Covered: [test_givenNoPosition_whenQueried][test_givenNoPosition_whenQueried] |
| BLLENS-POSITION-P03 | Fuzz all callers | Registered asset; borrower=0 with no position | (0,0,0,0) | Covered: [test_whenZeroBorrower][test_whenZeroBorrower] |
| BLLENS-POSITION-P01 | Fuzz all callers | Collateral-only position | (1000e6,0,0,0) | Covered: [test_givenCollateralOnly_whenQueried][test_givenCollateralOnly_whenQueried] |
| BLLENS-POSITION-P04 | Fuzz all callers | Active debt episode | (1000e6,100e9,T,B) | Covered: [test_givenActiveDebt_whenQueried][test_givenActiveDebt_whenQueried] |
| BLLENS-POSITION-P05 | Fuzz all callers | Repay 40e9 from the active episode | (1000e6,60e9,T,B) | Covered: [test_givenPartialRepayment_whenQueried][test_givenPartialRepayment_whenQueried] |
| BLLENS-POSITION-P06 | Fuzz all callers | Fully repay active episode | (1000e6,0,0,0); collateral retained, debt metadata cleared | Covered: [test_givenFullRepayment_whenQueried][test_givenFullRepayment_whenQueried] |
| BLLENS-POSITION-P07 | Fuzz all callers | Default active episode | (0,0,0,0) | Covered: [test_givenDefault_whenQueried][test_givenDefault_whenQueried] |
| BLLENS-POSITION-P08 | Fuzz all callers | Reopen a fully repaid episode with 70e9 debt in block B2 | (1000e6,70e9,T2,B2); no old episode metadata | Covered: [test_givenReopenedEpisode_whenQueried][test_givenReopenedEpisode_whenQueried] |
| BLLENS-POSITION-P09 | Fuzz all callers | Same borrower has different positions against X and Y; query X | Exact X tuple; Y collateral/debt/expiry excluded | Covered: [test_givenAnotherMarket_whenQueried][test_givenAnotherMarket_whenQueried] |
| BLLENS-POSITION-P10 | Fuzz all callers | Controlled FLOAN fixture has two positions for this market/borrower | First indexed position exactly; neither sum nor last position | Covered: [test_givenMultiplePositions_whenQueried][test_givenMultiplePositions_whenQueried] |

## Read dependency isolation

The canonical position remains unchanged while unrelated services change.

| ID | Caller | Independent transition / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-D01 | Fuzz all callers | Selected Risk.health/snapshot both configured to revert | Exact stored tuple; no Risk call | No writes | Covered: [test_givenBrokenRisk_whenQueried][test_givenBrokenRisk_whenQueried] |
| BLLENS-POSITION-D02 | Fuzz all callers | Core selects a new compatible Risk | Exact same stored tuple | No writes | Covered: [test_givenReplacementRisk_whenQueried][test_givenReplacementRisk_whenQueried] |
| BLLENS-POSITION-T01 | Fuzz all callers | Canonical FLOAN.getPosition rejects with controlled FloanReadFailed() | Exact FloanReadFailed() | No writes | Covered: [test_givenFloanFailure_whenQueried_reverts][test_givenFloanFailure_whenQueried_reverts] |

- [x] Review the scenarios.
- [x] Implement focused tests and update Test mappings.

[test_givenActiveDebt_whenQueried]: ./getPosition.t.sol#L84
[test_givenActiveDisabledCore_whenQueried]: ./getPosition.t.sol#L23
[test_givenActiveEnabledCore_whenQueried]: ./getPosition.t.sol#L17
[test_givenAnotherMarket_whenQueried]: ./getPosition.t.sol#L141
[test_givenBrokenRisk_whenQueried]: ./getPosition.t.sol#L174
[test_givenCollateralOnly_whenQueried]: ./getPosition.t.sol#L77
[test_givenDefault_whenQueried]: ./getPosition.t.sol#L115
[test_givenFloanFailure_whenQueried_reverts]: ./getPosition.t.sol#L199
[test_givenFullRepayment_whenQueried]: ./getPosition.t.sol#L107
[test_givenInactiveDisabledCore_whenQueried]: ./getPosition.t.sol#L35
[test_givenInactiveEnabledCore_whenQueried]: ./getPosition.t.sol#L29
[test_givenMultiplePositions_whenQueried]: ./getPosition.t.sol#L156
[test_givenNoPosition_whenQueried]: ./getPosition.t.sol#L67
[test_givenPartialRepayment_whenQueried]: ./getPosition.t.sol#L99
[test_givenReopenedEpisode_whenQueried]: ./getPosition.t.sol#L123
[test_givenReplacementRisk_whenQueried]: ./getPosition.t.sol#L191
[test_whenUnknownAsset_reverts]: ./getPosition.t.sol#L54
[test_whenZeroAsset_reverts]: ./getPosition.t.sol#L41
[test_whenZeroBorrower]: ./getPosition.t.sol#L72

[test_givenDisabledCore_whenLensReads_thenPositionRemainsVisible]: getPosition.t.sol#L230

# BurnerLoansLens.positionHealthFactor coverage plan

Source: [positionHealthFactor](../../../policies/burnerloans/BurnerLoansLens.sol#L96).

## Domains and notation

Scenario scope: `BLLENS-POSITION-HEALTH`. Lens stays a plain read-only helper without Kernel membership or IEnabler. SeizerTask owns operational control; Core is its immutable read dependency. All cases assert no state writes or committed events. `MAXn=2**n-1`.

Inputs collateral and debt are uint256 raw token amounts. Output H is WAD-scaled regardless of PRICE decimals. Zero debt returns MAX256 before any asset/Risk/price lookup. Debt-bearing quotes read the currently selected Risk snapshot, then health. Unit tests mock Risk to prove exact forwarding; the fixed integration cases below use actual Risk arithmetic.

## Core lifecycle independence

Read dependencies otherwise work. Core lifecycle flags do not impose admission on this helper.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-L01 | Fuzz all callers | true | true | Same result as corresponding valid query | No writes or logs | Covered: [test_givenActiveEnabledCore_whenQueried][test_givenActiveEnabledCore_whenQueried] |
| BLLENS-POSITION-HEALTH-L02 | Fuzz all callers | true | false | Same result as corresponding valid query | No writes or logs | Covered: [test_givenActiveDisabledCore_whenQueried][test_givenActiveDisabledCore_whenQueried] |
| BLLENS-POSITION-HEALTH-L03 | Fuzz all callers | false | true | Same result as corresponding valid query | No writes or logs | Covered: [test_givenInactiveEnabledCore_whenQueried][test_givenInactiveEnabledCore_whenQueried] |
| BLLENS-POSITION-HEALTH-L04 | Fuzz all callers | false | false | Same result as corresponding valid query | No writes or logs | Covered: [test_givenInactiveDisabledCore_whenQueried][test_givenInactiveDisabledCore_whenQueried] |

## Debt-free short circuits

Each row is separate. Configure Risk and price reads to reject if called. No borrower position lookup is required for this arithmetic API.

| ID | Caller | Asset / collateral / debt | Expected H | Dependency reads | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-I01 | Fuzz all callers | Asset=0; collateral=1; debt=0 | MAX256 | None | Covered: [test_givenZeroAsset_whenDebtIsZero][test_givenZeroAsset_whenDebtIsZero] |
| BLLENS-POSITION-HEALTH-P03 | Fuzz all callers | Nonzero unregistered asset; collateral=1; debt=0 | MAX256 | None | Covered: [test_givenUnknownAsset_whenDebtIsZero][test_givenUnknownAsset_whenDebtIsZero] |
| BLLENS-POSITION-HEALTH-P04 | Fuzz all callers | Registered asset; unavailable PRICE; collateral=1; debt=0 | MAX256 | None | Covered: [test_givenUnavailablePrice_whenDebtIsZero][test_givenUnavailablePrice_whenDebtIsZero] |
| BLLENS-POSITION-HEALTH-N01 | Fuzz all callers | Registered asset; collateral=0; debt=0 | MAX256 | None | Covered: [test_givenZeroCollateral_whenDebtIsZero][test_givenZeroCollateral_whenDebtIsZero] |
| BLLENS-POSITION-HEALTH-N02 | Fuzz all callers | Registered asset; collateral=MAX256; debt=0 | MAX256 | None; no narrowing | Covered: [test_givenMaximumCollateral_whenDebtIsZero][test_givenMaximumCollateral_whenDebtIsZero] |

## Invalid debt-bearing inputs

Debt=100e9. Except the varied fault, asset is registered and Risk snapshot/market configuration work. Use controlled snapshots where needed to ensure the intended error is reached.

| ID | Caller | Fault | Expected error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-I02 | Fuzz all callers | Asset=0; valid mocked snapshot; Core rejects the canonical market lookup | BurnerLoansCore_AssetNotConfigured(0) | No writes | Covered: [test_whenZeroDebtBearingAsset_reverts][test_whenZeroDebtBearingAsset_reverts] |
| BLLENS-POSITION-HEALTH-I03 | Fuzz all callers | Nonzero unregistered asset; valid mocked snapshot | BurnerLoansCore_AssetNotConfigured(asset) | No writes | Covered: [test_whenUnknownDebtBearingAsset_reverts][test_whenUnknownDebtBearingAsset_reverts] |
| BLLENS-POSITION-HEALTH-I04 | Fuzz all callers | Zero collateral USD observation; other snapshot inputs valid | IBurnerLoansRisk.BurnerLoans_InvalidPrice() | No writes | Covered: [test_givenZeroCollateralPrice_whenQuoted_reverts][test_givenZeroCollateralPrice_whenQuoted_reverts] |
| BLLENS-POSITION-HEALTH-I05 | Fuzz all callers | Zero OHM USD observation; other snapshot inputs valid | IBurnerLoansRisk.BurnerLoans_InvalidPrice() | No writes | Covered: [test_givenZeroOhmPrice_whenQuoted_reverts][test_givenZeroOhmPrice_whenQuoted_reverts] |
| BLLENS-POSITION-HEALTH-I06 | Fuzz all callers | Backing oracle returns zero; other prices valid | IBurnerLoansRisk.BurnerLoans_InvalidPrice() | No writes | Covered: [test_givenZeroBacking_whenQuoted_reverts][test_givenZeroBacking_whenQuoted_reverts] |
| BLLENS-POSITION-HEALTH-I07 | Fuzz all callers | Collateral timestamp=t; now=t+observationFrequency+1 | IBurnerLoansRisk.BurnerLoans_InvalidPrice() | No writes | Covered: [test_givenStalePrice_whenQuoted_reverts][test_givenStalePrice_whenQuoted_reverts] |

## Dependency failures

Positive debt and valid asset/configuration; isolate each failing Risk read.

| ID | Caller | Failing read | Expected error | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-T01 | Fuzz all callers | Risk.snapshot reverts with SnapshotReadFailed() | Exact SnapshotReadFailed() | No health call or writes | Covered: [test_givenSnapshotFailure_whenQuoted_reverts][test_givenSnapshotFailure_whenQuoted_reverts] |
| BLLENS-POSITION-HEALTH-T02 | Fuzz all callers | Snapshot valid; Risk.health reverts with RiskHealthFailed() | Exact RiskHealthFailed() | No writes | Covered: [test_givenHealthFailure_whenQuoted_reverts][test_givenHealthFailure_whenQuoted_reverts] |

## Risk handoff unit tests

Use snapshot S with distinct nonzero price/backing fields. Assert one snapshot(asset) and health(S,asset,collateral,debt), and return the independently mocked health unchanged. No local health algorithm or parameter validation is duplicated.

| ID | Caller | Fixed inputs / mocked return | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-P05 | Fuzz all callers | collateral=123; debt=456; mock H=7e17 | Exactly 7e17 | Covered: [test_givenArbitrary_whenHealthForwarded][test_givenArbitrary_whenHealthForwarded] |
| BLLENS-POSITION-HEALTH-N03 | Fuzz all callers | collateral=MAX256; debt=1; mock H=11 | Exactly 11; forward MAX256 collateral | Covered: [test_givenMaximumCollateral_whenHealthForwarded][test_givenMaximumCollateral_whenHealthForwarded] |
| BLLENS-POSITION-HEALTH-N04 | Fuzz all callers | collateral=1; debt=MAX256; mock H=13 | Exactly 13; forward MAX256 debt | Covered: [test_givenMaximumDebt_whenHealthForwarded][test_givenMaximumDebt_whenHealthForwarded] |
| BLLENS-POSITION-HEALTH-N05 | Fuzz all callers | collateral=1; debt=1; mock H=MAX256 | Exactly MAX256; no result narrowing | Covered: [test_givenMaximumHealth_whenHealthForwarded][test_givenMaximumHealth_whenHealthForwarded] |

## Fixed health arithmetic integration cases

Use real Risk. Defaults: collateral has 6 decimals, OHM 9, PRICE 6; C=1250e6, D=100e9; collateral/USD=1e6, OHM/USD=10e6; backing oracle=10e18; maxLtvBps=8500, backingMultiplierBps=12500. Debt market value is $1000; backing requires $1250, exceeding the market-LTV requirement. H=floor(collateral USD value*1e18/required USD). Inputs and expected integers stay fixed, not fuzzed.

| ID | Caller | One changed input | Manually derived expected H | Test |
| --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-P02 | Any caller | Defaults | 1250/1250 * 1e18 = 1e18 | Covered: [test_givenDefaults_whenRealHealthQuoted][test_givenDefaults_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N06 | Any caller | Collateral/USD=999999 | Collateral USD=1249998750 PRICE units; H=999999000000000000 | Covered: [test_givenCollateralBelow_whenRealHealthQuoted][test_givenCollateralBelow_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N07 | Any caller | Collateral/USD=1000001 | Collateral USD=1250001250 PRICE units; H=1000001000000000000 | Covered: [test_givenCollateralAbove_whenRealHealthQuoted][test_givenCollateralAbove_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N08 | Any caller | C=0, D=100e9 | 0; numeric health quote, no healthy-position admission | Covered: [test_givenZeroCollateral_whenRealHealthQuoted][test_givenZeroCollateral_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N09 | Any caller | C=1 raw collateral unit | floor(1 * 1e18 / 1250000000) = 800000000 | Covered: [test_givenOneRawCollateral_whenRealHealthQuoted][test_givenOneRawCollateral_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N10 | Any caller | Both USD prices=1 raw PRICE unit; backing unchanged | Backing still requires 1250000000 PRICE units; collateral value=1250; H=1000000000000 | Covered: [test_givenOneRawPrices_whenRealHealthQuoted][test_givenOneRawPrices_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N11 | Any caller | OHM=9, collateral=6, PRICE=18 decimals; equivalent economic amounts/prices | 1e18; output remains WAD | Covered: [test_givenOhm9Asset6Price18_whenRealHealthQuoted][test_givenOhm9Asset6Price18_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N12 | Any caller | OHM=9, collateral=18, PRICE=6 decimals; C=1250e18 | 1e18 | Covered: [test_givenOhm9Asset18Price6_whenRealHealthQuoted][test_givenOhm9Asset18Price6_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N13 | Any caller | OHM=9, collateral=18, PRICE=18 decimals; C=1250e18 | 1e18 | Covered: [test_givenOhm9Asset18Price18_whenRealHealthQuoted][test_givenOhm9Asset18Price18_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N14 | Any caller | OHM=18, collateral=6, PRICE=6 decimals; D=100e18 | 1e18 | Covered: [test_givenOhm18Asset6Price6_whenRealHealthQuoted][test_givenOhm18Asset6Price6_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N15 | Any caller | OHM=18, collateral=6, PRICE=18 decimals; D=100e18 | 1e18 | Covered: [test_givenOhm18Asset6Price18_whenRealHealthQuoted][test_givenOhm18Asset6Price18_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N16 | Any caller | OHM=18, collateral=18, PRICE=6 decimals; C=1250e18,D=100e18 | 1e18 | Covered: [test_givenOhm18Asset18Price6_whenRealHealthQuoted][test_givenOhm18Asset18Price6_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N17 | Any caller | OHM=18, collateral=18, PRICE=18 decimals; C=1250e18,D=100e18 | 1e18 | Covered: [test_givenOhm18Asset18Price18_whenRealHealthQuoted][test_givenOhm18Asset18Price18_whenRealHealthQuoted] |
| BLLENS-POSITION-HEALTH-N18 | Any caller | OHM=9, collateral=18, PRICE=6; C=1250000125e12; backing=10e18+1; OHM/USD=5e6 | Backing rounds up to 10000001 PRICE units; requirement=1250000125; collateral USD=1250000125; H=1e18 | Covered: [test_givenBackingRoundsUp_whenRealHealthQuoted][test_givenBackingRoundsUp_whenRealHealthQuoted] |

## Pricing and configuration transitions

Use the base integration fixture, except the selected-Risk mock replacement case. Change one dependency or parameter at a time; no cached health is retained.

| ID | Caller | Transition | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLLENS-POSITION-HEALTH-P01 | Fuzz all callers | Update current collateral/USD observation from 1e6 to 2e6 | H changes 1e18 to 2e18 | Covered: [test_givenCollateralPriceChanges_whenQuoted][test_givenCollateralPriceChanges_whenQuoted] |
| BLLENS-POSITION-HEALTH-P06 | Fuzz all callers | Update current OHM/USD observation from 10e6 to 20e6 | Market requirement=ceil(2000e6*10000/8500)=2352941177; H=531249999880468750 | Covered: [test_givenOhmPriceChanges_whenQuoted][test_givenOhmPriceChanges_whenQuoted] |
| BLLENS-POSITION-HEALTH-P07 | Fuzz all callers | Backing oracle changes backing 10e18 to 20e18 | Required USD doubles to $2500; H=5e17 | Covered: [test_givenBackingChanges_whenQuoted][test_givenBackingChanges_whenQuoted] |
| BLLENS-POSITION-HEALTH-P08 | Fuzz all callers | Core selects new compatible Risk; new mock returns 9e17 | Exactly 9e17; old Risk must not be queried | Covered: [test_givenReplacementRisk_whenQuoted][test_givenReplacementRisk_whenQuoted] |
| BLLENS-POSITION-HEALTH-P09 | Fuzz all callers | maxLtvBps changes from 8500 to 5000 | Market requirement=$2000; H=625000000000000000 | Covered: [test_givenLtvChanges_whenQuoted][test_givenLtvChanges_whenQuoted] |
| BLLENS-POSITION-HEALTH-P10 | Fuzz all callers | Governance replaces Risk backing oracle; new valid oracle backing=20e18 | H=5e17; previous oracle not queried | Covered: [test_givenReplacementOracleChanges_whenQuoted][test_givenReplacementOracleChanges_whenQuoted] |
| BLLENS-POSITION-HEALTH-P11 | Fuzz all callers | Governance replaces active supported price cache with fresh valid pair quoting collateral/USD=2e6 | H=2e18; current selected cache used without refresh writes | Covered: [test_givenReplacementActiveCache_whenQuoted][test_givenReplacementActiveCache_whenQuoted] |
| BLLENS-POSITION-HEALTH-P12 | Fuzz all callers | Kernel replaces PRICE with supported 18-decimal module, equivalent prices | H remains 1e18; lookup uses current module/decimal scale | Covered: [test_givenReplacementPriceModule_whenQuoted][test_givenReplacementPriceModule_whenQuoted] |

These are fixture/arithmetic precedents, not Covered mappings for this API. Keep fixed expected integers and update only mappings once tests prove the scenarios.

- [x] Review these expectations.
- [x] Implement focused tests and update Test mappings.

[test_givenActiveDisabledCore_whenQueried]: ./positionHealthFactor.t.sol#L29
[test_givenActiveEnabledCore_whenQueried]: ./positionHealthFactor.t.sol#L22
[test_givenArbitrary_whenHealthForwarded]: ./positionHealthFactor.t.sol#L141
[test_givenBackingChanges_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L264
[test_givenBackingRoundsUp_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L212
[test_givenCollateralAbove_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L55
[test_givenCollateralBelow_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L40
[test_givenCollateralPriceChanges_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L228
[test_givenDefaults_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L26
[test_givenHealthFailure_whenQuoted_reverts]: ./positionHealthFactor.t.sol#L194
[test_givenInactiveDisabledCore_whenQueried]: ./positionHealthFactor.t.sol#L43
[test_givenInactiveEnabledCore_whenQueried]: ./positionHealthFactor.t.sol#L36
[test_givenLtvChanges_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L282
[test_givenMaximumCollateral_whenDebtIsZero]: ./positionHealthFactor.t.sol#L94
[test_givenMaximumCollateral_whenHealthForwarded]: ./positionHealthFactor.t.sol#L147
[test_givenMaximumDebt_whenHealthForwarded]: ./positionHealthFactor.t.sol#L153
[test_givenMaximumHealth_whenHealthForwarded]: ./positionHealthFactor.t.sol#L159
[test_givenOhm18Asset18Price18_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L198
[test_givenOhm18Asset18Price6_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L184
[test_givenOhm18Asset6Price18_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L170
[test_givenOhm18Asset6Price6_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L156
[test_givenOhm9Asset18Price18_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L142
[test_givenOhm9Asset18Price6_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L128
[test_givenOhm9Asset6Price18_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L114
[test_givenOhmPriceChanges_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L246
[test_givenOneRawCollateral_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L84
[test_givenOneRawPrices_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L98
[test_givenReplacementActiveCache_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L387
[test_givenReplacementOracleChanges_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L303
[test_givenReplacementPriceModule_whenQuoted]: ./positionHealthFactorIntegration.t.sol#L367
[test_givenReplacementRisk_whenQuoted]: ./positionHealthFactor.t.sol#L207
[test_givenSnapshotFailure_whenQuoted_reverts]: ./positionHealthFactor.t.sol#L176
[test_givenStalePrice_whenQuoted_reverts]: ./positionHealthFactorIntegration.t.sol#L358
[test_givenUnavailablePrice_whenDebtIsZero]: ./positionHealthFactor.t.sol#L72
[test_givenUnknownAsset_whenDebtIsZero]: ./positionHealthFactor.t.sol#L61
[test_givenZeroAsset_whenDebtIsZero]: ./positionHealthFactor.t.sol#L50
[test_givenZeroBacking_whenQuoted_reverts]: ./positionHealthFactorIntegration.t.sol#L349
[test_givenZeroCollateralPrice_whenQuoted_reverts]: ./positionHealthFactorIntegration.t.sol#L323
[test_givenZeroCollateral_whenDebtIsZero]: ./positionHealthFactor.t.sol#L83
[test_givenZeroCollateral_whenRealHealthQuoted]: ./positionHealthFactorIntegration.t.sol#L70
[test_givenZeroOhmPrice_whenQuoted_reverts]: ./positionHealthFactorIntegration.t.sol#L336
[test_whenUnknownDebtBearingAsset_reverts]: ./positionHealthFactor.t.sol#L123
[test_whenZeroDebtBearingAsset_reverts]: ./positionHealthFactor.t.sol#L105

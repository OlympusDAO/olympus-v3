# BurnerLoansRisk.fee coverage plan

Source: [fee](../../../policies/burnerloans/BurnerLoansRisk.sol#L403). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-FEE` identifies this contract/function.

Permissionless view; canonical FLOAN market ID supplied, market debt token must match Risk OHM. principal:uint256 OHM, terms:uint16, snapshot prices:uint256. Utilization uses canonical market principal BEFORE the requested borrow; debt above cfg.debtCap rejects rather than clamps. Fee is returned in raw underlying collateral units, even when exits return vault shares. The API returns a fee, not utilization or a fee rate; intermediate values below are independent working, not additional return fields.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-L01 | Fuzz all callers | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenOperational_whenCalled], [test][test_givenReEnabled_whenCalled] |
| BLRISK-FEE-L02 | Fuzz all callers | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenCalled_reverts] |
| BLRISK-FEE-L03 | Fuzz all callers | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenCalled_reverts] |
| BLRISK-FEE-L04 | Fuzz all callers | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenCalled_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-I02 | Fuzz all callers | Market debt>0; cap=0 | BurnerLoans_InvalidCap() | Unchanged; no committed logs | Covered: [test][test_givenZeroCap_whenFeeQuoted_reverts] |
| BLRISK-FEE-I03 | Fuzz all callers | Market debt>cap>0 | BurnerLoans_InvalidCap() | Unchanged; no committed logs | Covered: [test][test_givenDebtAboveCap_whenFeeQuoted_reverts] |
| BLRISK-FEE-I07 | Fuzz all callers | terms=0; debt>0 and cap=0 | BurnerLoans_InvalidCap() | Unchanged; no committed logs | Covered: [test][test_givenZeroTermsAndZeroCap_whenFeeQuoted_reverts] |
| BLRISK-FEE-I08 | Fuzz all callers | terms=0; collateral price=0 | BurnerLoans_InvalidPrice() | Unchanged; no committed logs | Covered: [test][test_whenCollateralPriceIsZero_whenTermsAreZero_reverts] |
| BLRISK-FEE-I09 | Fuzz all callers | Market ID does not exist | FLOAN_InvalidMarket(marketId) | Unchanged; no committed logs | Covered: [test][test_whenMarketMissing_reverts] |

## Zero values and flat curves

These are successful read-only calculations; they are not invalid inputs. All other configuration and snapshot requirements still apply.

| ID | Caller | Calculation context | Execution / return | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-I01 | Fuzz all callers | Market debt=0; cap=0; valid prices | Utilization=0; calculate base fee | Independent value calculation; no state, token or event changes | Covered: [test][test_givenEmptyMarketZeroCap_whenFeeQuoted] |
| BLRISK-FEE-I04 | Fuzz all callers | kink=0; both slopes=0 | Flat base fee | Independent value calculation; no state, token or event changes | Covered: [test][test_givenZeroKinkFlatCurve_whenFeeQuoted] |
| BLRISK-FEE-I05 | Fuzz all callers | Valid calculations; principal=0 | Fee=0 | Independent value calculation; no state, token or event changes | Covered: [test][test_givenZeroPrincipal_whenFeeQuoted] |
| BLRISK-FEE-I06 | Fuzz all callers | Valid calculations; terms=0 | Fee=0; configuration/utilization calculations still run | Independent value calculation; no state, token or event changes | Covered: [test][test_givenZeroTerms_whenFeeQuoted] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-N01 | Fuzz all callers | Positive representable fee and terms; seed terms=1 and MAX16 | ceil(requiredAssets*feeRate/1e18)*terms | Round each term up before multiplying; no state changes | Covered: [test][test_whenTermsAndPrincipalAreRepresentable], [test][test_whenPrincipalAndTermEndpoints], [test][test_whenSnapshotFieldsAreMaximum] |
| BLRISK-FEE-N02 | Fuzz all callers | Final fee-per-term times terms exceeds MAX256 | `Panic(0x11)` | Unchanged; no committed logs | Covered: [test][test_whenFeePerTermTimesTermsOverflows_reverts] |
| BLRISK-FEE-N03 | Fuzz all callers | A called Math.mulDiv quotient exceeds MAX256; preceding operations representable | `Panic(0x11)` | Unchanged; no committed logs | Covered: [test][test_whenRequiredDebtValueOverflows_reverts] |
| BLRISK-FEE-N04 | Fuzz all callers | A called Math.mulDiv with ceil rounding floor quotient equals MAX256 with nonzero remainder; preceding operations representable | `Panic(0x11)` | Unchanged; no committed logs | Covered: [test][test_whenBackingRoundUpOverflows_thenFeeAndHealthRevert] |

## Successful execution

Fixed for this table: Accounting / events: Independent value calculation; no state, token or event changes.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-FEE-P01 | Fuzz all callers | Debt<cap; representable arithmetic | Utilization=ceil(debt*1e18/cap) | Covered: [test][test_whenUtilizationIsRoundedUp], [test][test_whenUtilizationRoundsUp] |
| BLRISK-FEE-P02 | Fuzz all callers | Debt=cap>0 | Utilization=1e18 | Covered: [test][test_givenAtCap_whenFeeQuoted] |
| BLRISK-FEE-P03 | Fuzz all callers | kink>0; utilization below kink | Pre-kink slope calculation | Covered: [test][test_givenBeforeKink_whenFeeQuoted] |
| BLRISK-FEE-P04 | Fuzz all callers | utilization equals kink | Exact continuous kink fee | Covered: [test][test_givenAtKink_whenFeeQuoted] |
| BLRISK-FEE-P05 | Fuzz all callers | utilization above kink | Post-kink slope calculation | Covered: [test][test_givenAfterKink_whenFeeQuoted] |

## Fixed utilization curve and fee outputs

Fixed caller; no caller or arithmetic fuzzing in these rows. Defaults: OHM decimals=9, collateral decimals=18, all three snapshot USD fields=1e18, principal=1e9, maxLtvBps=10000, backingMultiplierBps=10000, terms=1. Required collateral R=1e18 raw units: one OHM requires $1, converted to one collateral token. Curve is base=25, kink=8000, pre=100, post=900 bps. Market cap=1e18 raw OHM, so utilization WAD equals the fixed pre-existing market debt shown below. Debt is already recorded on FLOAN; requested principal does not enter utilization. Hard-code every fee and retain the working in test comments.

| ID | Caller | Pre-existing market debt | Working for rate / fee | Expected fee, raw collateral | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-P06 | Fixed caller | 0 | Base 25 bps; R times 0.0025 | 2500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsZero], [test][test_givenDefaultCurve_whenUtilizationIsZero_whenRiskIsCalled] |
| BLRISK-FEE-P07 | Fixed caller | 400000000000000000 | Half the pre-kink increase: 25+50=75 bps | 7500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint], [test][test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint_whenRiskIsCalled] |
| BLRISK-FEE-N05 | Fixed caller | 799999999999999999 | Pre contribution=floor((8e17-1)/80)=9999999999999999; add base 2500000000000000 | 12499999999999999 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink], [test][test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink_whenRiskIsCalled] |
| BLRISK-FEE-P08 | Fixed caller | 800000000000000000 | Full pre increase: 25+100=125 bps | 12500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsAtKink], [test][test_givenDefaultCurve_whenUtilizationIsAtKink_whenRiskIsCalled] |
| BLRISK-FEE-N06 | Fixed caller | 800000000000000001 | First post fraction=floor(900/2000)=0 WAD units; rate stays 125 bps | 12500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink], [test][test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink_whenRiskIsCalled] |
| BLRISK-FEE-P09 | Fixed caller | 900000000000000000 | Half post increase: 25+100+450=575 bps | 57500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint], [test][test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint_whenRiskIsCalled] |
| BLRISK-FEE-P10 | Fixed caller | 1000000000000000000 | Full curve: 25+100+900=1025 bps | 102500000000000000 | Covered: [test][test_givenDefaultCurve_whenUtilizationIsFull], [test][test_givenDefaultCurve_whenUtilizationIsFull_whenRiskIsCalled] |

## Precision, dust and per-term rounding

Use fixed inputs and literal outputs. Each case supplies its complete deviations from the defaults above. Intermediate conversions round up; curve slope contributions round down; fee per term rounds up before multiplication by terms. Do not derive expected values by calling LoanMath, Risk or a preview.

| ID | Caller | Fixed deviations / required collateral | Independent working | Expected fee, raw collateral | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-N07 | Fixed caller | Valid linear curve base=0,kink=5000,pre=5000,post=5000; market debt=999999999,cap=1000000000; principal=1000e9 gives R=1000e18 | Utilization=999999999000000000; fee rate equals utilization; 1000e18 times 0.999999999 | 999999999000000000000 | Covered: [test][test_whenUtilizationIsNearCap], [test][test_givenLinearCurve_whenUtilizationIsNearCap] |
| BLRISK-FEE-N08 | Fixed caller | Same valid linear curve; market debt=1,cap=1e36; principal=1e9 gives R=1e18 | ceil(1e18/1e36)=1 utilization WAD unit; pre-kink contribution=1; ceil(1e18*1/1e18)=1 | 1 | Covered: [test][test_whenNonzeroDebtIsTiny], [test][test_givenLinearCurve_whenDebtIsTiny] |
| BLRISK-FEE-N09 | Fixed caller | Flat curve base=1,kink=0,pre=post=0; principal=1 raw OHM; collateral decimals=6 | Required USD=1e9; R=ceil(1e9*1e6/1e18)=1; fee=ceil(1/10000)=1 | 1 | Covered: [test][test_givenFlatCurve_whenPrincipalIsOneRawOhmUnit] |
| BLRISK-FEE-N10 | Fixed caller | Flat 1-bps curve; principal=1000e9; collateral decimals=6; terms=3 | R=1000e6; fee/term=100000; three terms=300000 | 300000 | Covered: [test][test_givenFlatCurve_whenThreeTermsAreQuoted] |
| BLRISK-FEE-N11 | Fixed caller | Flat 1-bps curve; principal=1 raw OHM; collateral decimals=6; terms=3 | R=1; each term costs ceil(1/10000)=1; multiply 1*3, rather than ceil(3/10000) | 3 | Covered: [test][test_givenDustFee_whenThreeTermsAreQuoted] |
| BLRISK-FEE-N12 | Fixed caller | Flat 1-bps curve; principal=1 raw OHM; collateral decimals=6; terms=MAX16=65535 | R=1; fee/term=1; 65535 identical terms | 65535 | Covered: [test][test_givenDustFee_whenMaximumTermsAreQuoted] |
| BLRISK-FEE-N13 | Fixed caller | Flat 1-bps curve; collateral decimals=0; principal=9999e9 gives R=9999 | ceil(9999/10000)=1 | 1 | Covered: [test][test_givenFlatCurve_whenFeeIsImmediatelyBelowAnInteger] |
| BLRISK-FEE-N14 | Fixed caller | Same; principal=10000e9 gives R=10000 | Exact 10000/10000=1 | 1 | Covered: [test][test_givenFlatCurve_whenFeeIsExactlyAnInteger] |
| BLRISK-FEE-N15 | Fixed caller | Same; principal=10001e9 gives R=10001 | ceil(10001/10000)=2 | 2 | Covered: [test][test_givenFlatCurve_whenFeeIsImmediatelyAboveAnInteger] |
| BLRISK-FEE-N16 | Fixed caller | Flat 100%-fee curve; maxLtv=multiplier=10000; snapshot OHM/backing=1e9, collateral=1e6; collateral decimals=6; principal=MAX256; terms=1 | Debt USD=MAX256; collateral conversion is identity; rate=1e18 | MAX256; valid full-precision intermediates | Covered: [test][test_whenPrincipalAndTermEndpoints] |
| BLRISK-FEE-P11 | Fixed caller | Flat curve base=25,kink=0,pre=post=0; R=1e18 | Legal zero-kink curve is flat; 25/10000 of one collateral token | 2500000000000000 | Covered: [test][test_whenFlatBase] |
| BLRISK-FEE-P12 | Fixed caller | All fee components zero; valid R>0 | Rate=0, so rounding creates no fee | 0 | Covered: [test][test_whenZeroCurve] |

## Required collateral and decimal-scale examples

Fixed caller. Defaults: principal=1e9, OHM decimals=9, collateral decimals=6, PRICE decimals=18, flat fee base=100 bps, terms=1, maxLtv=10000, backing multiplier=10000, collateral/USD=1e18. Supply synthetic snapshots directly; no cache/oracle refresh is expected.

| ID | Caller | OHM / backing USD per token | Other deviation | Required collateral working | Expected fee | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-P13 | Fixed caller | 2e18 / 1e18 | None | Market binds at $2; R=2000000 | 20000 | Covered: [test][test_whenMarketRequirement] |
| BLRISK-FEE-P14 | Fixed caller | 1e18 / 2e18 | None | Backing binds at $2; R=2000000 | 20000 | Covered: [test][test_whenBackingRequirement] |
| BLRISK-FEE-P15 | Fixed caller | 2e18 / 2e18 | None | Equal $2 requirements; not their sum; R=2000000 | 20000 | Covered: [test][test_whenEqualRequirements] |
| BLRISK-FEE-P16 | Fixed caller | 2e18 / 1e18 | maxLtv=5000 | Market requires $4; R=4000000 | 40000 | Covered: [test][test_whenDiscountedLtv] |
| BLRISK-FEE-P17 | Fixed caller | 1e18 / 2e18 | Backing multiplier=12500 | Backing requires $2.50; R=2500000 | 25000 | Covered: [test][test_whenBackingMultiplier] |
| BLRISK-FEE-N17 | Fixed caller | 1e18 / 1e18 | Collateral/USD=3e18 | R=ceil(1e6/3)=333334; ceil(R/100)=3334 | 3334 | Covered: [test][test_whenCollateralConversionRoundsUp] |
| BLRISK-FEE-N18 | Fixed caller | 1e6 / 1e6 | PRICE decimals=6; collateral/USD=1e6 | Same $1 requirement; R=1000000 | 10000 | Covered: [test][test_whenSixPriceDecimals] |
| BLRISK-FEE-N19 | Fixed caller | 1e18 / 1e18 | OHM decimals=18; principal=1e18; collateral decimals=18 | Same $1 requirement; R=1e18 | 10000000000000000 | Covered: [test][test_whenEighteenOhmDecimals] |
| BLRISK-FEE-N20 | Fixed caller | 1e6 / 1e6 | PRICE decimals=6; collateral/USD=1e6; collateral decimals=18 | R=1e18; output follows collateral decimals, not PRICE | 10000000000000000 | Covered: [test][test_whenSixPriceEighteenCollateralDecimals] |

## Canonical market context and isolation

Risk active/enabled. Use the default fixed curve and stable prices unless specified. Change one context at a time. These are read-only quotes, not token-routing or borrowing-cap admission tests.

| ID | Caller | Context / fault | Execution / expected fee | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-FEE-D01 | Fuzz all callers | Existing market uses a different debt token; principal positive | BurnerLoansRisk_InvalidMarket(marketId) | No Core, token or mutable snapshot call | Covered: [test][test_whenDebtTokenDiffers_reverts] |
| BLRISK-FEE-D02 | Fuzz all callers | Existing market has incompatible product configId | BurnerLoans_IncompatibleMarketConfig(marketId,configId) | No state changes | Covered: [test][test_whenMarketSchemaDiffers_reverts] |
| BLRISK-FEE-P18 | Fixed caller | Selected market debt=3,cap=4; other market debt/global funding changes independently | 11875000000000000 | Only supplied market utilization enters the quote; do not read Inventory global utilization | Covered: [test][test_givenAnotherMarketHasDebt_whenSelectedMarketFeeIsQuoted], [test][test_givenGlobalFundingChanges_whenSelectedMarketFeeQuoted] |
| BLRISK-FEE-P19 | Fixed caller | Debt=4e17,cap=1e18; requested principal raised from 1e9 to 2e9 | Fee doubles to 15000000000000000 | Requested principal scales the requirement, not pre-borrow utilization | Covered: [test][test_givenExistingMarketDebt_whenRequestedPrincipalDoubles] |
| BLRISK-FEE-P20 | Fixed caller | Same economics as P07, but market exits change to shares | 7500000000000000 raw underlying units | No vault share-price read or fee denomination change | Covered: [test][test_whenMarketExitsAsShares] |
| BLRISK-FEE-P21 | Fixed caller | Core selects another Risk; quote this old still-active/enabled Risk directly | Own canonical market quote remains available | No Core-selection lookup or implied retirement gate | Covered: [test][test_givenReplacementSelected_whenOldRiskQuoted] |

## Shared assertions

Guarantee kink-adjacent debts where ceil(debt\*WAD/cap) crosses it; do not rely on random generation. Seed type maximum of every snapshot field/principal and UINT16_MAX terms. Independent fee examples prove units and rounding.

- [x] Review these expectations.
- [x] Implement named Foundry tests and boundary seed drivers.
- [x] Map each row to passing tests.

## Legacy regression cases to retain

Port high-precision kink±one WAD utilization unit, near-cap utilization avoiding basis-point quantization, fractional raw OHM principal, sum curve boundaries and per-term ceil before multiplication. Legacy zero-kink helper allowed a slope in isolated math harness, but production validated configuration allows only flat zero-kink curves: separate reachable from synthetic calculator cases.

## Original zero-kink helper regressions

Preserve the original helper-level inputs exactly. The legacy math helper supports a nonzero slope at zero kink, while the existing product validator rejects that configuration. These cases belong to the internal LoanMath test file and do not claim to establish acceptance through Risk.validateFeeConfig. No behavior change to that policy is approved here.

| ID | Caller | Original helper inputs / working | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-FEE-N21 | Fixed caller | U=0.9e18; base=25,kink=0,pre=1000,post=0; 25 bps + 90%*1000 bps | Rate=92500000000000000 WAD | Covered: [test][test_givenZeroKink_whenSlopeIsNonzero] |
| BLRISK-FEE-N22 | Fixed caller | U=999999999000000000; base=0,kink=0,pre=3333,post=0; floor(U*3333/10000) | Rate=333299999666700000 WAD | Covered: [test][test_givenZeroKink_whenSlopeContributionHasRemainder] |
| BLRISK-FEE-N23 | Fixed caller | U=999999999000000000; base=0,kink=0,pre=10000,post=0 | Rate=999999999000000000 WAD | Covered: [test][test_givenZeroKink_whenUtilizationIsNearCap] |
| BLRISK-FEE-N24 | Fixed caller | Same original zero-kink rate as N23; required collateral=1000e18 | Fee=999999999000000000000 raw collateral | Covered: [test][test_givenZeroKink_whenNearCapBorrowFeeIsCalculated] |
| BLRISK-FEE-P22 | Fixed caller | Default valid curve at kink, kink+0.0001e18 and 0.9e18 | Exact kink rate=12500000000000000; subsequent rates nondecreasing | Covered: [test][test_givenDefaultCurve_whenCrossingKink] |
| BLRISK-FEE-P23 | Fuzz utilization A in 0..1e18; B in A..1e18, with explicit endpoints | Default valid curve; compare independent ordered inputs | Rate(B)>=Rate(A); no case-selecting success/error branches | Covered: [test][test_givenDefaultCurve_whenUtilizationIncreases], [test][test_givenDefaultCurve_whenUtilizationEndpointsAreCompared] |

| ID | Caller | Original helper inputs / working | Expected result | Test |
| --- | --- | --- | --- | --- |
| BLRISK-FEE-N25 | Fixed caller | Required collateral=1000e6; rate=1e14 WAD (1 bps); ceil(1000e6/10000) | 100000 raw collateral units | Covered: [test][test_whenBorrowFeeIsCalculated] |

[test_givenAfterKink_whenFeeQuoted]: fee.t.sol#L279

[test_givenAnotherMarketHasDebt_whenSelectedMarketFeeIsQuoted]: feeIntegration.t.sol#L224

[test_givenAtCap_whenFeeQuoted]: fee.t.sol#L295

[test_givenAtKink_whenFeeQuoted]: fee.t.sol#L267

[test_givenBeforeKink_whenFeeQuoted]: fee.t.sol#L251

[test_givenDebtAboveCap_whenFeeQuoted_reverts]: fee.t.sol#L148

[test_givenDefaultCurve_whenCrossingKink]: ../../libraries/LoanMath/fee.t.sol#L153

[test_givenDefaultCurve_whenUtilizationEndpointsAreCompared]: ../../libraries/LoanMath/fee.t.sol#L226

[test_givenDefaultCurve_whenUtilizationIncreases]: ../../libraries/LoanMath/fee.t.sol#L204

[test_givenDefaultCurve_whenUtilizationIsAtKink]: ../../libraries/LoanMath/fee.t.sol#L65

[test_givenDefaultCurve_whenUtilizationIsAtKink_whenRiskIsCalled]: feeIntegration.t.sol#L57

[test_givenDefaultCurve_whenUtilizationIsFull]: ../../libraries/LoanMath/fee.t.sol#L95

[test_givenDefaultCurve_whenUtilizationIsFull_whenRiskIsCalled]: feeIntegration.t.sol#L90

[test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink]: ../../libraries/LoanMath/fee.t.sol#L73

[test_givenDefaultCurve_whenUtilizationIsOneWadAboveKink_whenRiskIsCalled]: feeIntegration.t.sol#L68

[test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink]: ../../libraries/LoanMath/fee.t.sol#L50

[test_givenDefaultCurve_whenUtilizationIsOneWadBelowKink_whenRiskIsCalled]: feeIntegration.t.sol#L46

[test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint]: ../../libraries/LoanMath/fee.t.sol#L86

[test_givenDefaultCurve_whenUtilizationIsPostKinkMidpoint_whenRiskIsCalled]: feeIntegration.t.sol#L79

[test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint]: ../../libraries/LoanMath/fee.t.sol#L41

[test_givenDefaultCurve_whenUtilizationIsPreKinkMidpoint_whenRiskIsCalled]: feeIntegration.t.sol#L35

[test_givenDefaultCurve_whenUtilizationIsZero]: ../../libraries/LoanMath/fee.t.sol#L32

[test_givenDefaultCurve_whenUtilizationIsZero_whenRiskIsCalled]: feeIntegration.t.sol#L24

[test_givenDisabled_whenCalled_reverts]: fee.t.sol#L101

[test_givenDustFee_whenMaximumTermsAreQuoted]: feeIntegration.t.sol#L164

[test_givenDustFee_whenThreeTermsAreQuoted]: feeIntegration.t.sol#L153

[test_givenEmptyMarketZeroCap_whenFeeQuoted]: fee.t.sol#L175

[test_givenExistingMarketDebt_whenRequestedPrincipalDoubles]: feeIntegration.t.sol#L208

[test_givenFlatCurve_whenFeeIsExactlyAnInteger]: feeIntegration.t.sol#L186

[test_givenFlatCurve_whenFeeIsImmediatelyAboveAnInteger]: feeIntegration.t.sol#L197

[test_givenFlatCurve_whenFeeIsImmediatelyBelowAnInteger]: feeIntegration.t.sol#L175

[test_givenFlatCurve_whenPrincipalIsOneRawOhmUnit]: feeIntegration.t.sol#L134

[test_givenFlatCurve_whenThreeTermsAreQuoted]: feeIntegration.t.sol#L142

[test_givenGlobalFundingChanges_whenSelectedMarketFeeQuoted]: feeIntegration.t.sol#L295

[test_givenInactiveAndDisabled_whenCalled_reverts]: fee.t.sol#L115

[test_givenInactive_whenCalled_reverts]: fee.t.sol#L108

[test_givenLinearCurve_whenDebtIsTiny]: feeIntegration.t.sol#L118

[test_givenLinearCurve_whenUtilizationIsNearCap]: feeIntegration.t.sol#L101

[test_givenOperational_whenCalled]: fee.t.sol#L95

[test_givenReEnabled_whenCalled]: fee.t.sol#L124

[test_givenReplacementSelected_whenOldRiskQuoted]: feeIntegration.t.sol#L315

[test_givenZeroCap_whenFeeQuoted_reverts]: fee.t.sol#L138

[test_givenZeroKinkFlatCurve_whenFeeQuoted]: fee.t.sol#L183

[test_givenZeroKink_whenNearCapBorrowFeeIsCalculated]: ../../libraries/LoanMath/fee.t.sol#L173

[test_givenZeroKink_whenSlopeContributionHasRemainder]: ../../libraries/LoanMath/fee.t.sol#L119

[test_givenZeroKink_whenSlopeIsNonzero]: ../../libraries/LoanMath/fee.t.sol#L103

[test_givenZeroKink_whenUtilizationIsNearCap]: ../../libraries/LoanMath/fee.t.sol#L136

[test_givenZeroPrincipal_whenFeeQuoted]: fee.t.sol#L190

[test_givenZeroTermsAndZeroCap_whenFeeQuoted_reverts]: fee.t.sol#L156

[test_givenZeroTerms_whenFeeQuoted]: fee.t.sol#L196

[test_whenBackingMultiplier]: fee.t.sol#L407

[test_whenBackingRequirement]: fee.t.sol#L332

[test_whenBackingRoundUpOverflows_thenFeeAndHealthRevert]: fee.t.sol#L73

[test_whenBorrowFeeIsCalculated]: ../../libraries/LoanMath/fee.t.sol#L166

[test_whenCollateralConversionRoundsUp]: fee.t.sol#L432

[test_whenCollateralPriceIsZero_whenTermsAreZero_reverts]: fee.t.sol#L24

[test_whenDebtTokenDiffers_reverts]: fee.t.sol#L528

[test_whenDiscountedLtv]: fee.t.sol#L382

[test_whenEighteenOhmDecimals]: fee.t.sol#L489

[test_whenEqualRequirements]: fee.t.sol#L357

[test_whenFeePerTermTimesTermsOverflows_reverts]: fee.t.sol#L50

[test_whenFlatBase]: fee.t.sol#L510

[test_whenMarketExitsAsShares]: fee.t.sol#L554

[test_whenMarketMissing_reverts]: fee.t.sol#L166

[test_whenMarketRequirement]: fee.t.sol#L307

[test_whenMarketSchemaDiffers_reverts]: fee.t.sol#L539

[test_whenNonzeroDebtIsTiny]: ../../libraries/LoanMath/fee.t.sol#L220

[test_whenPrincipalAndTermEndpoints]: fee.t.sol#L220

[test_whenRequiredDebtValueOverflows_reverts]: fee.t.sol#L37

[test_whenSixPriceDecimals]: fee.t.sol#L457

[test_whenSixPriceEighteenCollateralDecimals]: fee.t.sol#L473

[test_whenSnapshotFieldsAreMaximum]: fee.t.sol#L568

[test_whenTermsAndPrincipalAreRepresentable]: fee.t.sol#L202

[test_whenUtilizationIsNearCap]: ../../libraries/LoanMath/fee.t.sol#L20

[test_whenUtilizationIsRoundedUp]: ../../libraries/LoanMath/fee.t.sol#L191

[test_whenUtilizationRoundsUp]: fee.t.sol#L236

[test_whenZeroCurve]: fee.t.sol#L521

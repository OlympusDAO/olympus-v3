// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoans} from "src/policies/BurnerLoans.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansMathTest is BurnerLoansTest {
    function _assertHealthFactorLevels(
        uint256 debtOhm_,
        uint8 ohmDecimals_,
        uint8 collateralDecimals_
    ) internal view {
        // debt = 100 OHM at $10 = $1,000, regardless of OHM token decimals.
        uint256 debtValueUsd = burnerLoans.debtValueUsd(debtOhm_, 10e18, ohmDecimals_);
        assertEq(debtValueUsd, 1_000e18, "manual debt USD value");

        // required collateral = $1,000 * 115% = $1,150.
        // Below: $1,035 / $1,150 = 0.9e18 health.
        // Boundary: $1,150 / $1,150 = 1e18 health.
        // Above: $1,265 / $1,150 = 1.1e18 health.
        uint256 collateralScale = 10 ** collateralDecimals_;
        uint256 belowCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_035 * collateralScale,
            1e18,
            collateralDecimals_
        );
        uint256 boundaryCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_150 * collateralScale,
            1e18,
            collateralDecimals_
        );
        uint256 aboveCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_265 * collateralScale,
            1e18,
            collateralDecimals_
        );

        assertEq(belowCollateralValueUsd, 1_035e18, "manual below-boundary USD value");
        assertEq(boundaryCollateralValueUsd, 1_150e18, "manual boundary USD value");
        assertEq(aboveCollateralValueUsd, 1_265e18, "manual above-boundary USD value");

        // Collateral factor = 100%, so each risk-adjusted value remains unchanged.
        uint256 belowRiskAdjustedUsd = burnerLoans.riskAdjustedCollateralUsd(
            belowCollateralValueUsd,
            10_000
        );
        uint256 boundaryRiskAdjustedUsd = burnerLoans.riskAdjustedCollateralUsd(
            boundaryCollateralValueUsd,
            10_000
        );
        uint256 aboveRiskAdjustedUsd = burnerLoans.riskAdjustedCollateralUsd(
            aboveCollateralValueUsd,
            10_000
        );
        assertEq(belowRiskAdjustedUsd, 1_035e18, "manual below-boundary risk value");
        assertEq(boundaryRiskAdjustedUsd, 1_150e18, "manual boundary risk value");
        assertEq(aboveRiskAdjustedUsd, 1_265e18, "manual above-boundary risk value");

        assertEq(
            burnerLoans.healthFactor(belowRiskAdjustedUsd, 1_150e18),
            0.9e18,
            "manual below-boundary health factor"
        );
        assertEq(
            burnerLoans.healthFactor(boundaryRiskAdjustedUsd, 1_150e18),
            1e18,
            "manual boundary health factor"
        );
        assertEq(
            burnerLoans.healthFactor(aboveRiskAdjustedUsd, 1_150e18),
            1.1e18,
            "manual above-boundary health factor"
        );

        _assertHealthFactorImmediatelyAroundBoundary(collateralDecimals_);
    }

    function _assertHealthFactorImmediatelyAroundBoundary(uint8 collateralDecimals_) internal view {
        uint256 collateralScale = 10 ** collateralDecimals_;
        uint256 oneCollateralUnitUsd = collateralDecimals_ == 6 ? 1e12 : 1;

        uint256 belowCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_150 * collateralScale - 1,
            1e18,
            collateralDecimals_
        );
        uint256 aboveCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_150 * collateralScale + 1,
            1e18,
            collateralDecimals_
        );

        // The nearest native collateral units map to 1e12 USD units for 6 decimals
        // and one USD unit for 18 decimals.
        assertEq(
            belowCollateralValueUsd,
            1_150e18 - oneCollateralUnitUsd,
            "immediate below-boundary USD value"
        );
        assertEq(
            aboveCollateralValueUsd,
            1_150e18 + oneCollateralUnitUsd,
            "immediate above-boundary USD value"
        );

        uint256 belowHealthFactor = burnerLoans.healthFactor(
            burnerLoans.riskAdjustedCollateralUsd(belowCollateralValueUsd, 10_000),
            1_150e18
        );
        uint256 aboveHealthFactor = burnerLoans.healthFactor(
            burnerLoans.riskAdjustedCollateralUsd(aboveCollateralValueUsd, 10_000),
            1_150e18
        );

        // 6-decimal collateral moves health by floor/ceil(1e12 / 1,150).
        // 18-decimal collateral one unit below rounds health down by one WAD unit;
        // one unit above is below WAD precision and remains exactly 1e18.
        uint256 expectedBelowHealth = collateralDecimals_ == 6
            ? 999_999_999_130_434_782
            : 999_999_999_999_999_999;
        uint256 expectedAboveHealth = collateralDecimals_ == 6 ? 1_000_000_000_869_565_217 : 1e18;
        assertEq(belowHealthFactor, expectedBelowHealth, "immediate below-boundary health");
        assertEq(aboveHealthFactor, expectedAboveHealth, "immediate above-boundary health");
    }

    function test_debtValueUsd_givenPriceDecimalsAreNotWad_usesPriceScale() public view {
        // debt = 4e9 OHM units = 4 OHM with 9 decimals
        // price = 250e8 USD/OHM with 8 PRICE decimals
        // Expected: ceil(4e9 * 250e8 / 1e9) = 1000e8
        assertEq(burnerLoans.debtValueUsd(4e9, 250e8, OHM_DECIMALS), 1000e8, "debt value");
    }

    function test_debtValueUsd_givenTinyDebt_roundsUp() public view {
        // debt = 1 wei OHM, price = 10e18, OHM decimals = 9
        // Expected: ceil(1 * 10e18 / 1e9) = 10e9
        assertEq(burnerLoans.debtValueUsd(1, 10e18, OHM_DECIMALS), 10e9, "debt value");
    }

    function test_debtValueUsd_givenFractionalOhm_preservesPrecisionBeforeDivision() public view {
        // debt = 1.5 OHM = 1.5e9, price = 100e18
        // Expected: ceil(1.5e9 * 100e18 / 1e9) = 150e18
        // An early division by OHM decimals would incorrectly produce 100e18.
        assertEq(
            burnerLoans.debtValueUsd(1_500_000_000, 100e18, OHM_DECIMALS),
            150e18,
            "debt value"
        );
    }

    function test_collateralValueUsd_givenSixDecimalCollateral_roundsDown() public view {
        // collateral = 1 smallest USDS unit = 0.000001 USDS, price = 1e18
        // Expected: floor(1 * 1e18 / 1e6) = 1e12
        assertEq(burnerLoans.collateralValueUsd(1, 1e18, USDS_DECIMALS), 1e12, "collateral value");
    }

    function test_collateralValueUsd_givenFractionalCollateral_preservesPrecisionBeforeDivision()
        public
        view
    {
        // collateral = 1.5 USDS = 1.5e6, price = 1e18
        // Expected: floor(1.5e6 * 1e18 / 1e6) = 1.5e18
        // An early division by collateral decimals would incorrectly produce 1e18.
        assertEq(
            burnerLoans.collateralValueUsd(1_500_000, 1e18, USDS_DECIMALS),
            1.5e18,
            "collateral value"
        );
    }

    function test_collateralValueUsd_givenEighteenDecimalCollateral_matchesSixDecimalValue()
        public
        view
    {
        // 6-decimal collateral: 1.5e6 at 1 USD => 1.5e18 USD value
        // 18-decimal collateral: 1.5e18 at 1 USD => 1.5e18 USD value
        assertEq(
            burnerLoans.collateralValueUsd(1_500_000, 1e18, 6),
            burnerLoans.collateralValueUsd(1.5e18, 1e18, 18),
            "normalized value"
        );
    }

    function test_riskAdjustedCollateralUsd_roundsDown() public view {
        // collateral value = 1000e18, collateral factor = 3333 bps
        // Expected: floor(1000e18 * 3333 / 10000) = 333.3e18
        assertEq(burnerLoans.riskAdjustedCollateralUsd(1000e18, 3333), 333.3e18, "risk adjusted");
    }

    function test_requiredCollateralUsd_takesMaxOfMarketAndBackingRequirement() public view {
        // debt value = 1000e18; min CR = 11500 bps => market requirement = 1150e18
        // debt = 4 OHM; backing = 12e18; multiplier = 10000 bps => backing requirement = 48e18
        // Expected max = 1150e18
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoans.RequiredCollateralUsdInputs({
                    debtValueUsd: 1000e18,
                    debtOhm: 4e9,
                    backingPerOhmUsd: 12e18,
                    minCollateralRatioBps: 11_500,
                    backingMultiplierBps: 10_000
                })
            ),
            1150e18,
            "required collateral"
        );
    }

    function test_requiredCollateralUsd_givenBackingDominates_takesBackingRequirement()
        public
        view
    {
        // debt value = 10e18; min CR = 11000 bps => market requirement = 11e18
        // debt = 4 OHM; backing = 12e18; multiplier = 15000 bps => backing requirement = 72e18
        // Expected max = 72e18
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoans.RequiredCollateralUsdInputs({
                    debtValueUsd: 10e18,
                    debtOhm: 4e9,
                    backingPerOhmUsd: 12e18,
                    minCollateralRatioBps: 11_000,
                    backingMultiplierBps: 15_000
                })
            ),
            72e18,
            "required collateral"
        );
    }

    function test_requiredCollateralAsset_roundsUp() public view {
        // required = 1e18 + 1 PRICE units, collateral price = 1e18, collateral decimals = 6
        // Expected: ceil((1e18 + 1) * 1e6 / 1e18) = 1,000,001
        assertEq(
            burnerLoans.requiredCollateralAsset(1e18 + 1, 1e18, USDS_DECIMALS),
            1_000_001,
            "required asset"
        );
    }

    function test_healthFactor_givenDebtFree_returnsMaxUint() public view {
        assertEq(burnerLoans.healthFactor(0, 0), type(uint256).max, "health factor");
    }

    function test_healthFactor_givenAtBoundary_returnsOneWad() public view {
        // debt = 4 OHM at 250 USD = 1000e18 debt value
        // required = 1000e18 * 11500 / 10000 = 1150e18
        // collateral = 1150 USDS at 1 USD = 1150e18
        // Expected: floor(1150e18 * 1e18 / 1150e18) = 1e18
        assertEq(burnerLoans.healthFactor(1150e18, 1150e18), 1e18, "health factor");
    }

    function test_healthFactor_givenNineDecimalDebtAndSixDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        _assertHealthFactorLevels(100e9, 9, 6);
    }

    function test_healthFactor_givenEighteenDecimalDebtAndSixDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        _assertHealthFactorLevels(100e18, 18, 6);
    }

    function test_healthFactor_givenNineDecimalDebtAndEighteenDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        _assertHealthFactorLevels(100e9, 9, 18);
    }

    function test_healthFactor_givenEighteenDecimalDebtAndEighteenDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        _assertHealthFactorLevels(100e18, 18, 18);
    }

    function test_healthFactor_givenOneWeiAboveBoundary_roundsDownToOneWad() public view {
        // collateral = 1150e18 + 1 wei, required = 1150e18
        // Expected: floor((1150e18 + 1) * 1e18 / 1150e18)
        //         = floor(1e18 + 1 / 1150)
        //         = 1e18
        // The one-wei excess is smaller than WAD health-factor precision.
        assertEq(burnerLoans.healthFactor(1150e18 + 1, 1150e18), 1e18, "health factor");
    }

    function test_healthFactor_givenOneWeiBelowBoundary_roundsDownBelowOneWad() public view {
        // collateral = 1150e18 - 1 wei, required = 1150e18
        // Expected: floor((1150e18 - 1) * 1e18 / 1150e18)
        //         = floor(1e18 - 1 / 1150)
        //         = 1e18 - 1
        assertEq(
            burnerLoans.healthFactor(1150e18 - 1, 1150e18),
            999_999_999_999_999_999,
            "health factor"
        );
    }

    function test_healthFactor_givenSixDecimalCollateralOneUnitAboveBoundary_roundsDown()
        public
        view
    {
        uint256 collateralValueUsd = burnerLoans.collateralValueUsd(1150e6 + 1, 1e18, 6);
        uint256 riskAdjustedCollateralUsd = burnerLoans.riskAdjustedCollateralUsd(
            collateralValueUsd,
            10_000
        );

        // collateral = 1150e6 + 1 native unit, collateral price = 1e18
        // collateral value = floor((1150e6 + 1) * 1e18 / 1e6) = 1150e18 + 1e12
        // required = 1150e18
        // Expected: floor((1150e18 + 1e12) * 1e18 / 1150e18)
        //         = 1e18 + floor(1e12 / 1150)
        //         = 1_000_000_000_869_565_217
        assertEq(
            burnerLoans.healthFactor(riskAdjustedCollateralUsd, 1150e18),
            1_000_000_000_869_565_217,
            "health factor"
        );
    }

    function test_healthFactor_givenSixDecimalCollateralOneUnitBelowBoundary_roundsDown()
        public
        view
    {
        uint256 collateralValueUsd = burnerLoans.collateralValueUsd(1150e6 - 1, 1e18, 6);
        uint256 riskAdjustedCollateralUsd = burnerLoans.riskAdjustedCollateralUsd(
            collateralValueUsd,
            10_000
        );

        // collateral = 1150e6 - 1 native unit, collateral price = 1e18
        // collateral value = floor((1150e6 - 1) * 1e18 / 1e6) = 1150e18 - 1e12
        // required = 1150e18
        // Expected: floor((1150e18 - 1e12) * 1e18 / 1150e18)
        //         = 1e18 - ceil(1e12 / 1150)
        //         = 999_999_999_130_434_782
        assertEq(
            burnerLoans.healthFactor(riskAdjustedCollateralUsd, 1150e18),
            999_999_999_130_434_782,
            "health factor"
        );
    }

    function test_utilizationBps_roundsUp() public view {
        // debt = 1, cap = 3
        // Expected: ceil(1 * 10000 / 3) = 3334
        assertEq(burnerLoans.utilizationBps(1, 3), 3334, "utilization");
    }

    function test_assetUtilizationWad_preservesPrecisionNearCap() public view {
        // debt = 999,999,999; cap = 1,000,000,000
        // Expected: ceil(999999999 * 1e18 / 1000000000) = 999999999000000000
        // A bps-scaled utilization would collapse this to 10000 bps and lose the fractional detail.
        assertEq(
            burnerLoans.assetUtilizationWad(999_999_999, 1_000_000_000),
            999_999_999_000_000_000,
            "asset utilization"
        );
    }

    function test_effectiveUtilizationWad_usesAssetUtilizationOnly() public view {
        // global utilization would be 90%, but global utilization is a capacity check only.
        // asset utilization = ceil(3 * 1e18 / 4) = 0.75e18
        // Expected fee input = asset utilization only.
        assertEq(
            burnerLoans.effectiveUtilizationWad(
                BurnerLoans.UtilizationInputs({assetDebtOhm: 3, assetDebtCapOhm: 4})
            ),
            0.75e18,
            "effective utilization"
        );
    }

    function test_effectiveUtilizationWad_givenTinyNonZeroAssetDebt_roundsUpToOneWadUnit()
        public
        view
    {
        // asset utilization = ceil(1 * 1e18 / 1e36) = 1 WAD unit
        // Expected non-zero utilization instead of truncating to zero.
        assertEq(
            burnerLoans.effectiveUtilizationWad(
                BurnerLoans.UtilizationInputs({assetDebtOhm: 1, assetDebtCapOhm: 1e36})
            ),
            1,
            "effective utilization"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base, 100 bps pre-kink slope, 900 bps post-kink slope
    // - Utilization: zero
    // - Expected branch: only the base fee contributes
    function test_feeRateWad_givenZeroUtilization() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // base = 25 bps = 25 / 10,000 = 0.0025 WAD
        // Pre-kink contribution = 0; post-kink contribution = 0.
        assertEq(
            burnerLoans.feeRateWad(0, feeConfig),
            2_500_000_000_000_000,
            "zero utilization base fee"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base and 100 bps full pre-kink increase
    // - Utilization: 40%, halfway to the 80% kink
    // - Expected branch: base plus half of the pre-kink slope
    function test_feeRateWad_givenPreKinkMidpoint() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Pre-kink contribution = 100 bps * 40% / 80% = 50 bps.
        // Total = 25 bps + 50 bps = 75 bps = 0.0075 WAD.
        assertEq(
            burnerLoans.feeRateWad(0.4e18, feeConfig),
            7_500_000_000_000_000,
            "pre-kink midpoint fee"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base and 100 bps full pre-kink increase
    // - Utilization: one WAD unit below the 80% kink
    // - Expected branch: pre-kink component rounds down by one WAD unit
    function test_feeRateWad_givenOneWadUnitBelowKink() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // At the kink, the pre-kink contribution is 0.01 WAD.
        // One utilization WAD unit below the kink gives floor((0.8e18 - 1) / 80)
        // = 9,999,999,999,999,999. Adding the 0.0025 WAD base gives:
        // 12,499,999,999,999,999.
        assertEq(
            burnerLoans.feeRateWad(0.8e18 - 1, feeConfig),
            12_499_999_999_999_999,
            "fee immediately below kink"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base and 100 bps full pre-kink increase
    // - Utilization: exactly at the 80% kink
    // - Expected branch: the entire pre-kink slope contributes and post-kink contributes zero
    function test_feeRateWad_givenUtilizationAtKink() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Total = 25 bps base + 100 bps pre-kink = 125 bps = 0.0125 WAD.
        assertEq(burnerLoans.feeRateWad(0.8e18, feeConfig), 12_500_000_000_000_000, "fee at kink");
    }

    // Condition tree:
    // - Fee curve: 25 bps base, 100 bps pre-kink slope, 900 bps post-kink slope
    // - Utilization: one WAD unit above the 80% kink
    // - Expected branch: the first post-kink fraction rounds down to zero
    function test_feeRateWad_givenOneWadUnitAboveKink() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Post-kink contribution = floor(1 * 900e18 / (0.2e18 * 10,000)) = 0.
        // Total therefore remains 25 bps + 100 bps = 125 bps.
        assertEq(
            burnerLoans.feeRateWad(0.8e18 + 1, feeConfig),
            12_500_000_000_000_000,
            "fee immediately above kink"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base, 100 bps pre-kink slope, 900 bps post-kink slope
    // - Utilization: 90%, halfway from the 80% kink to full utilization
    // - Expected branch: base and pre-kink components plus half the post-kink slope
    function test_feeRateWad_givenPostKinkMidpoint() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Post-kink contribution = 900 bps * (90% - 80%) / (100% - 80%) = 450 bps.
        // Total = 25 bps + 100 bps + 450 bps = 575 bps = 0.0575 WAD.
        assertEq(
            burnerLoans.feeRateWad(0.9e18, feeConfig),
            57_500_000_000_000_000,
            "post-kink midpoint fee"
        );
    }

    // Condition tree:
    // - Fee curve: 25 bps base, 100 bps pre-kink slope, 900 bps post-kink slope
    // - Utilization: 100%
    // - Expected branch: every configured fee component contributes in full
    function test_feeRateWad_givenFullUtilization() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        // Total = 25 bps + 100 bps + 900 bps = 1,025 bps = 0.1025 WAD.
        assertEq(
            burnerLoans.feeRateWad(1e18, feeConfig),
            102_500_000_000_000_000,
            "full utilization fee"
        );
    }

    function test_feeRateWad_givenNoKink_usesSlope1AcrossFullRange() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 25,
            kinkBps: 0,
            preKinkSlopeBps: 1000,
            postKinkSlopeBps: 0
        });

        // base = 25 bps = 0.0025e18
        // utilization = 90% = 0.9e18
        // preKinkSlope = 1000 bps = 10%
        // Expected: 0.0025e18 + floor(0.9e18 * 1000 / 10000) = 0.0925e18
        assertEq(burnerLoans.feeRateWad(0.9e18, feeConfig), 0.0925e18, "single slope fee");
    }

    function test_feeRateWad_componentsRoundDownAndDoNotDivideBpsFirst() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 3333,
            postKinkSlopeBps: 0
        });

        // utilization = 999999999000000000 / 1e18
        // preKinkSlope = 3333 bps
        // Expected: floor(999999999000000000 * 3333 / 10000)
        //         = 333299999666700000
        // Dividing utilization by 1e18 before multiplying would incorrectly return zero.
        assertEq(
            burnerLoans.feeRateWad(999_999_999_000_000_000, feeConfig),
            333_299_999_666_700_000,
            "fee rate"
        );
    }

    function test_feeRateWad_givenNearCapUtilization_doesNotQuantizeToBps() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });
        uint256 utilizationWad = burnerLoans.assetUtilizationWad(999_999_999, 1_000_000_000);

        // utilization = 999999999000000000 / 1e18 = 99.9999999%
        // preKinkSlope = 10000 bps = 100%, so expected fee rate equals utilization.
        // A bps path would produce either 9999 bps (0.9999e18) if floored or 10000 bps (1e18)
        // if rounded up. The WAD path preserves the exact 0.999999999e18 fee rate.
        assertEq(
            burnerLoans.feeRateWad(utilizationWad, feeConfig),
            999_999_999_000_000_000,
            "fee rate"
        );
    }

    function test_feeRateWad_isMonotonicAndContinuousAtKink() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        uint256 atKink = burnerLoans.feeRateWad(0.8e18, feeConfig);
        uint256 justAboveKink = burnerLoans.feeRateWad(0.8001e18, feeConfig);
        uint256 aboveKink = burnerLoans.feeRateWad(0.9e18, feeConfig);

        assertEq(atKink, 0.0125e18, "at kink");
        assertGe(justAboveKink, atKink, "kink continuity");
        assertGe(aboveKink, justAboveKink, "monotonic");
    }

    function test_borrowFee_roundsUp() public view {
        // required collateral = 1000e6, fee rate = 1 bps = 0.0001e18
        // Expected: ceil(1000e6 * 0.0001e18 / 1e18) = 100000
        assertEq(burnerLoans.borrowFee(1000e6, 0.0001e18), 100_000, "borrow fee");
    }

    function test_borrowFee_givenNearCapUtilization_doesNotLosePrecision() public view {
        IBurnerLoans.AssetFeeConfig memory feeConfig = IBurnerLoans.AssetFeeConfig({
            baseFeeBps: 0,
            kinkBps: 0,
            preKinkSlopeBps: 10_000,
            postKinkSlopeBps: 0
        });
        uint256 utilizationWad = burnerLoans.assetUtilizationWad(999_999_999, 1_000_000_000);
        uint256 feeRateWad = burnerLoans.feeRateWad(utilizationWad, feeConfig);

        // required collateral = 1000e18
        // fee rate = 999999999000000000 / 1e18
        // Expected: ceil(1000e18 * 999999999000000000 / 1e18)
        //         = 999999999000000000000
        assertEq(burnerLoans.borrowFee(1000e18, feeRateWad), 999_999_999e12, "borrow fee");
    }

    function test_extensionFee_scalesLinearlyWithTermCount() public view {
        // single term fee = ceil(1000e6 * 0.0001e18 / 1e18) = 100000
        // term count = 3 => 300000
        assertEq(burnerLoans.extensionFee(1000e6, 0.0001e18, 3), 300_000, "extension fee");
    }

    function test_keeperRewardAsset_givenProtocolSeizer_returnsZero() public view {
        assertEq(
            burnerLoans.keeperRewardAsset(
                BurnerLoans.KeeperRewardInputs({
                    isProtocolSeizureCaller: true,
                    seizedCollateralAmount: 1000e6,
                    seizedUnrepaidDebtOhm: 90e9,
                    backingPerOhmUsd: 10e18,
                    backingMultiplierBps: 10_000,
                    collateralUsdPrice: 1e18,
                    collateralDecimals: USDS_DECIMALS,
                    rewardBps: 1000,
                    maxKeeperRewardAsset: 100e6
                })
            ),
            0,
            "keeper reward"
        );
    }

    function test_keeperRewardAsset_givenZeroRewardSettings_returnsZero() public view {
        assertEq(
            burnerLoans.keeperRewardAsset(
                BurnerLoans.KeeperRewardInputs({
                    isProtocolSeizureCaller: false,
                    seizedCollateralAmount: 1000e6,
                    seizedUnrepaidDebtOhm: 90e9,
                    backingPerOhmUsd: 10e18,
                    backingMultiplierBps: 10_000,
                    collateralUsdPrice: 1e18,
                    collateralDecimals: USDS_DECIMALS,
                    rewardBps: 0,
                    maxKeeperRewardAsset: 100e6
                })
            ),
            0,
            "zero reward bps"
        );
        assertEq(
            burnerLoans.keeperRewardAsset(
                BurnerLoans.KeeperRewardInputs({
                    isProtocolSeizureCaller: false,
                    seizedCollateralAmount: 1000e6,
                    seizedUnrepaidDebtOhm: 90e9,
                    backingPerOhmUsd: 10e18,
                    backingMultiplierBps: 10_000,
                    collateralUsdPrice: 1e18,
                    collateralDecimals: USDS_DECIMALS,
                    rewardBps: 1000,
                    maxKeeperRewardAsset: 0
                })
            ),
            0,
            "zero max reward"
        );
    }

    function test_keeperRewardAsset_isCappedBySurplusAfterRequiredBacking() public view {
        // seized collateral = 1000 USDS
        // seized debt = 90 OHM, backing = 10 USD/OHM, multiplier = 10000 bps
        // required backing = 900 USDS, surplus = 100 USDS
        // configured reward = min(floor(1000 * 2000 / 10000), 150) = 150 USDS
        // Expected reward = min(150, 100) = 100 USDS
        assertEq(
            burnerLoans.keeperRewardAsset(
                BurnerLoans.KeeperRewardInputs({
                    isProtocolSeizureCaller: false,
                    seizedCollateralAmount: 1000e6,
                    seizedUnrepaidDebtOhm: 90e9,
                    backingPerOhmUsd: 10e18,
                    backingMultiplierBps: 10_000,
                    collateralUsdPrice: 1e18,
                    collateralDecimals: USDS_DECIMALS,
                    rewardBps: 2000,
                    maxKeeperRewardAsset: 150e6
                })
            ),
            100e6,
            "keeper reward"
        );
    }

    function testFuzz_utilizationBps_roundsUp(uint256 debt_, uint256 cap_) public view {
        cap_ = bound(cap_, 1, 1e36);
        debt_ = bound(debt_, 0, cap_);

        uint256 utilizationBps = burnerLoans.utilizationBps(debt_, cap_);

        assertGe(utilizationBps * cap_, debt_ * 10_000, "rounded up lower bound");
        if (utilizationBps > 0) {
            assertLt((utilizationBps - 1) * cap_, debt_ * 10_000, "minimal rounded up value");
        }
    }

    function testFuzz_assetUtilizationWad_roundsUp(uint256 debt_, uint256 cap_) public view {
        cap_ = bound(cap_, 1, 1e36);
        debt_ = bound(debt_, 0, cap_);

        uint256 utilizationWad = burnerLoans.assetUtilizationWad(debt_, cap_);

        assertGe(utilizationWad * cap_, debt_ * 1e18, "rounded up lower bound");
        if (utilizationWad > 0) {
            assertLt((utilizationWad - 1) * cap_, debt_ * 1e18, "minimal rounded up value");
        }
    }

    function testFuzz_feeRateWad_isMonotonic(
        uint128 utilizationA_,
        uint128 utilizationB_
    ) public view {
        uint256 utilizationA = bound(utilizationA_, 0, 1e18);
        uint256 utilizationB = bound(utilizationB_, utilizationA, 1e18);
        IBurnerLoans.AssetFeeConfig memory feeConfig = _defaultAssetFeeConfig();

        assertGe(
            burnerLoans.feeRateWad(utilizationB, feeConfig),
            burnerLoans.feeRateWad(utilizationA, feeConfig),
            "fee monotonic"
        );
    }
}

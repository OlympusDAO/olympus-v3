// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansHarness} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarness.sol";

import {BurnerLoansTest} from "./BurnerLoansTest.sol";

contract BurnerLoansMathTest is BurnerLoansTest {
    function _assertHealthFactorLevels(
        uint256 debtOhm_,
        uint8 ohmDecimals_,
        uint8 collateralDecimals_,
        uint256 expectedBoundaryCollateralValueUsd_,
        uint256 expectedBoundaryHealthFactor_,
        uint256 expectedImmediateBelowHealthFactor_,
        uint256 expectedImmediateAboveHealthFactor_
    ) internal view {
        // debt = 100 OHM at $10 = $1,000, regardless of OHM token decimals.
        uint256 debtValueUsd = burnerLoans.debtValueUsd(debtOhm_, 10e18, ohmDecimals_);
        assertEq(debtValueUsd, 1_000e18, "manual debt USD value");

        // maxLtvBps = 8,500 (basis points).
        // required collateral = ceil($1,000 * 10,000 / 8,500)
        //                     = 1,176.470588235294117648e18 (18 decimals).
        // Use exactly 85%, 100%, and 115% of that requirement for the health checks.
        uint256 requiredCollateralUsd = burnerLoans.requiredCollateralUsd(
            BurnerLoansHarness.RequiredCollateralUsdInputs({
                debtValueUsd: debtValueUsd,
                debtOhm: debtOhm_,
                backingPerOhmUsd: 0,
                maxLtvBps: 8_500,
                backingMultiplierBps: 10_000
            })
        );
        assertEq(
            requiredCollateralUsd,
            1_176_470_588_235_294_117_648,
            "85% maximum LTV requirement"
        );

        uint256 collateralScale = 10 ** collateralDecimals_;
        uint256 belowCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_000 * collateralScale,
            1e18,
            collateralDecimals_
        );
        uint256 boundaryCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_176_470_588_235_294_117_648 / (10 ** (18 - collateralDecimals_)),
            1e18,
            collateralDecimals_
        );
        uint256 aboveCollateralValueUsd = burnerLoans.collateralValueUsd(
            1_353 * collateralScale,
            1e18,
            collateralDecimals_
        );

        assertEq(belowCollateralValueUsd, 1_000e18, "manual below-boundary USD value");
        assertEq(
            boundaryCollateralValueUsd,
            expectedBoundaryCollateralValueUsd_,
            "manual boundary USD value"
        );
        assertEq(aboveCollateralValueUsd, 1_353e18, "manual above-boundary USD value");

        assertEq(
            burnerLoans.healthFactor(belowCollateralValueUsd, requiredCollateralUsd),
            849_999_999_999_999_999,
            "manual below-boundary health factor"
        );
        uint256 boundaryHealthFactor = burnerLoans.healthFactor(
            boundaryCollateralValueUsd,
            requiredCollateralUsd
        );
        assertEq(
            boundaryHealthFactor,
            expectedBoundaryHealthFactor_,
            "manual boundary health factor"
        );
        assertEq(
            burnerLoans.healthFactor(aboveCollateralValueUsd, requiredCollateralUsd),
            1_150_049_999_999_999_999,
            "manual above-boundary health factor"
        );

        _assertHealthFactorImmediatelyAroundBoundary(
            collateralDecimals_,
            requiredCollateralUsd,
            expectedImmediateBelowHealthFactor_,
            expectedImmediateAboveHealthFactor_
        );
    }

    function _assertHealthFactorImmediatelyAroundBoundary(
        uint8 collateralDecimals_,
        uint256 requiredCollateralUsd_,
        uint256 expectedBelowHealthFactor_,
        uint256 expectedAboveHealthFactor_
    ) internal view {
        uint256 boundaryCollateral = requiredCollateralUsd_ / (10 ** (18 - collateralDecimals_));

        uint256 belowCollateralValueUsd = burnerLoans.collateralValueUsd(
            boundaryCollateral - 1,
            1e18,
            collateralDecimals_
        );
        uint256 aboveCollateralValueUsd = burnerLoans.collateralValueUsd(
            boundaryCollateral + 1,
            1e18,
            collateralDecimals_
        );

        uint256 belowHealthFactor = burnerLoans.healthFactor(
            belowCollateralValueUsd,
            requiredCollateralUsd_
        );
        uint256 aboveHealthFactor = burnerLoans.healthFactor(
            aboveCollateralValueUsd,
            requiredCollateralUsd_
        );

        assertEq(belowHealthFactor, expectedBelowHealthFactor_, "immediate below-boundary health");
        assertEq(aboveHealthFactor, expectedAboveHealthFactor_, "immediate above-boundary health");
    }

    function test_debtValueUsd_givenPriceDecimalsAreNotWad_usesPriceScale() public view {
        // debt = 1.234567890 OHM with 9 decimals
        // price = 2.50000001 USD/OHM with 8 PRICE decimals
        // Expected: ceil(1_234_567_890 * 250_000_001 / 1e9) = 308_641_974 (8 decimals).
        assertEq(
            burnerLoans.debtValueUsd(1_234_567_890, 250_000_001, OHM_DECIMALS),
            308_641_974,
            "fractional debt value"
        );
    }

    function test_debtValueUsd_givenNonWadPriceScaleAndSmallestValues_roundsUp() public view {
        // One smallest OHM unit at one smallest 8-decimal price unit is below one USD price unit.
        // Expected: ceil(1 * 1 / 1e9) = 1, proving nonzero dust is not truncated to zero.
        assertEq(burnerLoans.debtValueUsd(1, 1, OHM_DECIMALS), 1, "smallest debt value");
    }

    function test_debtValueUsd_givenNonWadPriceScaleAndFractionalDust_roundsUp() public view {
        // 123 smallest OHM units at a 7-unit price still remain below one 8-decimal USD unit.
        // Expected: ceil(123 * 7 / 1e9) = 1.
        assertEq(burnerLoans.debtValueUsd(123, 7, OHM_DECIMALS), 1, "fractional dust value");
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

    function test_requiredCollateralUsd_whenMarketBranchDominates_usesMaximumLtv() public view {
        // debt market value = 100 OHM * $12 = 1,200e18 (18 decimals).
        // market requirement = ceil(1,200e18 * 10,000 / 8,500)
        //                    = 1,411.764705882352941177e18 (18 decimals).
        // backing requirement = 100 OHM * $10 * 12,500 / 10,000 = 1,250e18.
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1_200e18,
                    debtOhm: 100e9,
                    backingPerOhmUsd: 10e18,
                    maxLtvBps: 8_500,
                    backingMultiplierBps: 12_500
                })
            ),
            1_411_764_705_882_352_941_177,
            "market requirement"
        );
    }

    function test_requiredCollateralUsd_whenBackingBranchDominates_usesBackingMultiplier()
        public
        view
    {
        // debt market value = 100 OHM * $10 = 1,000e18 (18 decimals).
        // market requirement = ceil(1,000e18 * 10,000 / 8,500)
        //                    = 1,176.470588235294117648e18.
        // backing requirement = 100 OHM * $10 * 12,500 / 10,000 = 1,250e18.
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1_000e18,
                    debtOhm: 100e9,
                    backingPerOhmUsd: 10e18,
                    maxLtvBps: 8_500,
                    backingMultiplierBps: 12_500
                })
            ),
            1_250e18,
            "backing requirement"
        );
    }

    function test_requiredCollateralUsd_whenBranchesMeetAtCrossover_returnsSameRequirement()
        public
        view
    {
        // debt market value = 1,062.5e18 (106.25% of $1,000 backing value).
        // market requirement = 1,062.5e18 / 85% = 1,250e18.
        // backing requirement = 1,000e18 * 125% = 1,250e18.
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1_062.5e18,
                    debtOhm: 100e9,
                    backingPerOhmUsd: 10e18,
                    maxLtvBps: 8_500,
                    backingMultiplierBps: 12_500
                })
            ),
            1_250e18,
            "crossover requirement"
        );
    }

    function test_requiredCollateralUsd_whenMaximumLtvIsOneBps_usesConservativeRequirement()
        public
        view
    {
        // debt market value = 1e18 (18 decimals).
        // requirement = ceil(1e18 * 10,000 / 1) = 10,000e18.
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1e18,
                    debtOhm: 0,
                    backingPerOhmUsd: 1e18,
                    maxLtvBps: 1,
                    backingMultiplierBps: 10_000
                })
            ),
            10_000e18,
            "one bps maximum LTV requirement"
        );
    }

    function test_requiredCollateralUsd_whenMaximumLtvIsOneHundredPercent_matchesDebtValue()
        public
        view
    {
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1_000e18,
                    debtOhm: 0,
                    backingPerOhmUsd: 1e18,
                    maxLtvBps: 10_000,
                    backingMultiplierBps: 10_000
                })
            ),
            1_000e18,
            "one hundred percent maximum LTV requirement"
        );
    }

    function test_requiredCollateralUsd_whenMarketRequirementHasRemainder_roundsUp() public view {
        // debt market value = 1 (18-decimal USD unit).
        // Expected: ceil(1 * 10,000 / 8,500) = 2 USD units.
        assertEq(
            burnerLoans.requiredCollateralUsd(
                BurnerLoansHarness.RequiredCollateralUsdInputs({
                    debtValueUsd: 1,
                    debtOhm: 0,
                    backingPerOhmUsd: 1e18,
                    maxLtvBps: 8_500,
                    backingMultiplierBps: 10_000
                })
            ),
            2,
            "rounded-up market requirement"
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

    function test_launchStress_givenFivePercentCollateralDepeg_healthIsNinetyFivePercent()
        public
        view
    {
        // collateral = 1,250e6 (6 decimals), price = 0.95e18 (18 decimals).
        // collateral value = floor(1,250e6 * 0.95e18 / 1e6) = 1,187.5e18 USD.
        // required collateral = 1,250e18 USD under the backing branch.
        // health = floor(1,187.5e18 * 1e18 / 1,250e18) = 0.95e18.
        uint256 collateralValueUsd = burnerLoans.collateralValueUsd(
            1_250e6,
            0.95e18,
            USDS_DECIMALS
        );

        assertEq(collateralValueUsd, 1_187.5e18, "depegged collateral value");
        assertEq(
            burnerLoans.healthFactor(collateralValueUsd, 1_250e18),
            0.95e18,
            "five percent depeg health"
        );
    }

    function test_launchStress_givenTwentyPercentCollateralDepeg_coversBackingExactly()
        public
        view
    {
        // collateral = 1,250e6 (6 decimals), price = 0.80e18 (18 decimals).
        // collateral value = floor(1,250e6 * 0.80e18 / 1e6) = 1,000e18 USD.
        // required collateral = 1,250e18 USD, so health = 0.80e18.
        // The remaining $1,000 equals 100 OHM * $10 backing before realization losses.
        uint256 collateralValueUsd = burnerLoans.collateralValueUsd(1_250e6, 0.8e18, USDS_DECIMALS);

        assertEq(collateralValueUsd, 1_000e18, "depegged collateral value");
        assertEq(
            burnerLoans.healthFactor(collateralValueUsd, 1_250e18),
            0.8e18,
            "twenty percent depeg health"
        );
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
        // boundary collateral = floor(1_176.470588235294117648e18 / 1e12)
        //                     = 1_176_470_588 units (6 decimals).
        // boundary value = 1_176_470_588 * 1e12 = 1_176.470588e18 USD (18 decimals).
        // boundary health = floor(1_176.470588e18 * 1e18 / requirement)
        //                 = 0.999999999799999999e18 (18 decimals).
        _assertHealthFactorLevels(
            100e9,
            9,
            6,
            1_176_470_588_000_000_000_000,
            999_999_999_799_999_999,
            999_999_998_949_999_999,
            1_000_000_000_649_999_999
        );
    }

    function test_healthFactor_givenEighteenDecimalDebtAndSixDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        // Six-decimal collateral rounds the boundary down to 1_176_470_588 native units.
        // The resulting 18-decimal USD value and health factors match the explicit values below.
        _assertHealthFactorLevels(
            100e18,
            18,
            6,
            1_176_470_588_000_000_000_000,
            999_999_999_799_999_999,
            999_999_998_949_999_999,
            1_000_000_000_649_999_999
        );
    }

    function test_healthFactor_givenNineDecimalDebtAndEighteenDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        // Eighteen-decimal collateral represents the exact required USD boundary.
        _assertHealthFactorLevels(
            100e9,
            9,
            18,
            1_176_470_588_235_294_117_648,
            1e18,
            999_999_999_999_999_999,
            1e18
        );
    }

    function test_healthFactor_givenEighteenDecimalDebtAndEighteenDecimalCollateral_returnsExpectedLevels()
        public
        view
    {
        // Eighteen-decimal collateral represents the exact required USD boundary.
        _assertHealthFactorLevels(
            100e18,
            18,
            18,
            1_176_470_588_235_294_117_648,
            1e18,
            999_999_999_999_999_999,
            1e18
        );
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
        // collateral = 1150e6 + 1 native unit, collateral price = 1e18
        // collateral value = floor((1150e6 + 1) * 1e18 / 1e6) = 1150e18 + 1e12
        // required = 1150e18
        // Expected: floor((1150e18 + 1e12) * 1e18 / 1150e18)
        //         = 1e18 + floor(1e12 / 1150)
        //         = 1_000_000_000_869_565_217
        assertEq(
            burnerLoans.healthFactor(collateralValueUsd, 1150e18),
            1_000_000_000_869_565_217,
            "health factor"
        );
    }

    function test_healthFactor_givenSixDecimalCollateralOneUnitBelowBoundary_roundsDown()
        public
        view
    {
        uint256 collateralValueUsd = burnerLoans.collateralValueUsd(1150e6 - 1, 1e18, 6);
        // collateral = 1150e6 - 1 native unit, collateral price = 1e18
        // collateral value = floor((1150e6 - 1) * 1e18 / 1e6) = 1150e18 - 1e12
        // required = 1150e18
        // Expected: floor((1150e18 - 1e12) * 1e18 / 1150e18)
        //         = 1e18 - ceil(1e12 / 1150)
        //         = 999_999_999_130_434_782
        assertEq(
            burnerLoans.healthFactor(collateralValueUsd, 1150e18),
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
                BurnerLoansHarness.UtilizationInputs({assetDebtOhm: 3, assetDebtCapOhm: 4})
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
                BurnerLoansHarness.UtilizationInputs({assetDebtOhm: 1, assetDebtCapOhm: 1e36})
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
                BurnerLoansHarness.KeeperRewardInputs({
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
                BurnerLoansHarness.KeeperRewardInputs({
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
                BurnerLoansHarness.KeeperRewardInputs({
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
                BurnerLoansHarness.KeeperRewardInputs({
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

    function test_launchStress_givenRewardBelowBackingSurplus_paysConfiguredOnePercent()
        public
        view
    {
        // seized collateral = 1,300e6 (6 decimals) at $1e18 = $1,300.
        // backing floor = 100e9 OHM * $10e18 * 12,500 / 10,000 = $1,250.
        // configured reward = floor(1,300e6 * 100 / 10,000) = 13e6.
        // surplus = 50e6, so reward = min(13e6, 50e6, 100e6) = 13e6.
        uint256 reward = burnerLoans.keeperRewardAsset(
            BurnerLoansHarness.KeeperRewardInputs({
                isProtocolSeizureCaller: false,
                seizedCollateralAmount: 1_300e6,
                seizedUnrepaidDebtOhm: 100e9,
                backingPerOhmUsd: 10e18,
                backingMultiplierBps: 12_500,
                collateralUsdPrice: 1e18,
                collateralDecimals: USDS_DECIMALS,
                rewardBps: 100,
                maxKeeperRewardAsset: 100e6
            })
        );

        assertEq(reward, 13e6, "one percent keeper reward");
        assertEq(1_300e6 - reward, 1_287e6, "treasury collateral after reward");
    }

    function test_launchStress_givenRewardAboveBackingSurplus_preservesBackingFloor() public view {
        // seized collateral = 1,255e6 (6 decimals) at $1e18 = $1,255.
        // backing floor = 100e9 OHM * $10e18 * 12,500 / 10,000 = $1,250.
        // configured reward = floor(1,255e6 * 100 / 10,000) = 12.55e6.
        // surplus = 5e6, so reward = min(12.55e6, 5e6, 100e6) = 5e6.
        uint256 reward = burnerLoans.keeperRewardAsset(
            BurnerLoansHarness.KeeperRewardInputs({
                isProtocolSeizureCaller: false,
                seizedCollateralAmount: 1_255e6,
                seizedUnrepaidDebtOhm: 100e9,
                backingPerOhmUsd: 10e18,
                backingMultiplierBps: 12_500,
                collateralUsdPrice: 1e18,
                collateralDecimals: USDS_DECIMALS,
                rewardBps: 100,
                maxKeeperRewardAsset: 100e6
            })
        );

        assertEq(reward, 5e6, "surplus-limited keeper reward");
        assertEq(1_255e6 - reward, 1_250e6, "backing floor retained");
    }

    function test_utilizationBps_roundsUp(uint256 debt_, uint256 cap_) public view {
        cap_ = bound(cap_, 1, 1e36);
        debt_ = bound(debt_, 0, cap_);

        uint256 utilizationBps = burnerLoans.utilizationBps(debt_, cap_);

        assertGe(utilizationBps * cap_, debt_ * 10_000, "rounded up lower bound");
        if (utilizationBps > 0) {
            assertLt((utilizationBps - 1) * cap_, debt_ * 10_000, "minimal rounded up value");
        }
    }

    function test_assetUtilizationWad_roundsUp(uint256 debt_, uint256 cap_) public view {
        cap_ = bound(cap_, 1, 1e36);
        debt_ = bound(debt_, 0, cap_);

        uint256 utilizationWad = burnerLoans.assetUtilizationWad(debt_, cap_);

        assertGe(utilizationWad * cap_, debt_ * 1e18, "rounded up lower bound");
        if (utilizationWad > 0) {
            assertLt((utilizationWad - 1) * cap_, debt_ * 1e18, "minimal rounded up value");
        }
    }

    function test_feeRateWad_isMonotonic(uint128 utilizationA_, uint128 utilizationB_) public view {
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

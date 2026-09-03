// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansBorrowDecimalsTest is BurnerLoansBorrowTestBase {
    struct LaunchBoundaryScenario {
        uint128 decimalScaleCollateral;
        uint256 decimalScaleFee;
        uint256 decimalScaleHealth;
        uint128 fuzzCollateral;
        uint256 rawUnitFee;
        uint128 exactHundredPercentLtvCollateral;
        uint128 belowCollateral;
        uint256 belowHealth;
        uint128 minimumHealthyCollateral;
        uint256 minimumHealthyHealth;
        uint128 aboveCollateral;
        uint256 aboveHealth;
    }

    function _priceDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function _launchBoundaryScenario()
        internal
        pure
        virtual
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 18 decimals; collateral: 6 decimals.
        // For the fixed decimal-scale case, debtValueUsd = 100e9 OHM * $10.25e18 / 1e9
        // = $1_025e18 and requiredUsd = ceil($1_025e18 * 10_000 / 8_500)
        // = $1_205_882_352_941_176_470_589.
        // decimalScaleCollateral = ceil(requiredUsd * 1e6 / $0.75e18) = 1_607_843_138.
        // Its USD value is $1_205_882_353_500_000_000_000, so decimalScaleHealth
        // = floor($1_205_882_353_500_000_000_000 * 1e18 / requiredUsd)
        // = 1_000_000_000_463_414_634.
        // decimalScaleFee = ceil(1_607_843_138 * 25 / 10_000) = 4_019_608.
        // The one-raw-unit fee is 1 for both OHM decimal variants after rounding up.
        // debtValueUsd = 100e9 OHM * $10e18 / 1e9 = $1_000e18.
        // launchRequiredUsd = ceil($1_000e18 * 10_000 / 8_500)
        //                   = $1_176_470_588_235_294_117_648.
        // minimumHealthyCollateral = ceil(launchRequiredUsd * 1e6 / $1e18)
        //                          = 1_176_470_589.
        // At 100% LTV, requiredUsd = $1_000e18, so collateral = $1_000e18 * 1e6 / $1e18
        // = 1_000e6, and health = floor($1_000e18 * 1e18 / $1_000e18) = 1e18.
        // belowCollateral = minimumHealthyCollateral - 1 = 1_176_470_588.
        // Its USD value is 1_176_470_588 * $1e18 / 1e6 = $1_176_470_588e12, so
        // belowHealth = floor($1_176_470_588e12 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_799_999_999.
        // minimumHealthyCollateral = 1_176_470_589, with USD value $1_176_470_589e12, so
        // minimumHealthyHealth = floor($1_176_470_589e12 * 1e18 / launchRequiredUsd)
        //                      = 1_000_000_000_649_999_999.
        // aboveCollateral = minimumHealthyCollateral + 1 = 1_176_470_590, with USD value
        // $1_176_470_590e12, so aboveHealth = floor($1_176_470_590e12 * 1e18 /
        // launchRequiredUsd) = 1_000_000_001_499_999_999.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_138,
                decimalScaleFee: 4_019_608,
                decimalScaleHealth: 1_000_000_000_463_414_634,
                fuzzCollateral: 20_000_000e6,
                rawUnitFee: 1,
                exactHundredPercentLtvCollateral: 1_000e6,
                belowCollateral: 1_176_470_588,
                belowHealth: 999_999_999_799_999_999,
                minimumHealthyCollateral: 1_176_470_589,
                minimumHealthyHealth: 1_000_000_000_649_999_999,
                aboveCollateral: 1_176_470_590,
                aboveHealth: 1_000_000_001_499_999_999
            });
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Borrow amount: fixed at 100 whole OHM
    // - Prices: fractional values exercise scale conversion without whole-number shortcuts
    // - Expected values: fixed literals for the concrete decimal configuration
    function test_givenFixedBorrowAmount_borrowUsesConfiguredDecimalScales() public {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _assertBorrowUsesConfiguredDecimalScales(
            uint128(100 * 10 ** _ohmDecimals()),
            scenario.decimalScaleCollateral,
            scenario.decimalScaleFee,
            scenario.decimalScaleHealth
        );
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Borrow amount: fuzzed from one raw OHM unit through 100 whole OHM
    // - Maximum LTV: fuzzed across the complete valid interval of 1 through 10,000 bps
    // - Prices: fixed at $10.25 per OHM and $0.75 per collateral token
    // - Collateral: fixed at 20,000,000 whole tokens, sufficient even when maximum LTV is 1 bp
    // - Expected branch: preview and write agree without deriving an expected value from formulas
    function test_whenBorrowAmountAndMaximumLtvAreValid_borrowMatchesPreviewAcrossConfiguredDecimalScales(
        uint128 borrowAmount_,
        uint16 maxLtvBps_
    ) public {
        uint128 borrowAmount = uint128(
            bound(uint256(borrowAmount_), 1, 100 * 10 ** _ohmDecimals())
        );
        uint16 maxLtvBps = uint16(bound(uint256(maxLtvBps_), 1, 10_000));

        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxLtvBps = maxLtvBps;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);

        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _assertBorrowMatchesPreview(borrowAmount, scenario.fuzzCollateral);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Borrow amount: one smallest native OHM unit
    // - Expected branch: debt and fee retain their fixed nonzero native-unit values
    function test_givenOneRawOhmUnit_borrowDoesNotTruncateValuesToZero() public {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _configureFractionalPrices();
        _depositFractionalPriceCollateral(scenario.fuzzCollateral);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            1,
            alice
        );

        assertTrue(preview.executable, "raw-unit preview executable");
        assertEq(preview.fee, scenario.rawUnitFee, "raw-unit preview fee");
        assertEq(preview.resultingDebtOhm, 1, "raw-unit preview debt");

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), 1, alice, alice, scenario.rawUnitFee);

        assertEq(borrowedOhm, 1, "raw-unit borrowed OHM");
        assertEq(fee, scenario.rawUnitFee, "raw-unit fee");
        assertEq(totalDebtOhm, 1, "raw-unit debt");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "raw-unit preview debt");
        assertEq(maturity, preview.maturity, "raw-unit preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "raw-unit preview health");
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Maximum LTV: 100%, making the market requirement equal to debt market value
    // - Market requirement: 100 OHM * $10 / 100% = $1,000
    // - Backing requirement: 100 OHM * $1 backing * 125% = $125, so the market branch governs
    // - Collateral: exactly $1,000 at $1 per collateral token
    // - Expected branch: preview and borrow return exactly 1e18 health
    function test_givenHundredPercentMaximumLtv_whenAtExactBoundary_borrowReturnsOneWad() public {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxLtvBps = 10_000;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);

        _assertSuccessfulHealthBoundaryBorrow(scenario.exactHundredPercentLtvCollateral, 1e18);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Maximum LTV: launch value of 85%
    // - Collateral: fixed minimum healthy amount for the concrete decimal configuration
    // - Expected branch: preview and borrow return the fixed rounded health factor
    function test_givenLaunchMaximumLtv_whenAtMinimumHealthyCollateral_borrowReturnsExpectedHealth()
        public
    {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _assertSuccessfulHealthBoundaryBorrow(
            scenario.minimumHealthyCollateral,
            scenario.minimumHealthyHealth
        );
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Collateral: one smallest native unit below the minimum healthy amount
    // - Expected branch: preview and borrow revert with the exact rounded health factor
    function test_givenLaunchMaximumLtv_whenOneCollateralUnitBelowHealthBoundary_reverts() public {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _configureBoundaryPrices();
        _depositBoundaryCollateral(scenario.belowCollateral);

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
            scenario.belowHealth
        );
        uint128 borrowAmount = uint128(100 * 10 ** _ohmDecimals());

        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), borrowAmount, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), borrowAmount, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Collateral: one smallest native unit above the minimum healthy amount
    // - Expected branch: preview and borrow return the exact rounded health factor
    function test_givenLaunchMaximumLtv_whenOneCollateralUnitAboveHealthBoundary_borrowReturnsExpectedHealth()
        public
    {
        LaunchBoundaryScenario memory scenario = _launchBoundaryScenario();
        _assertSuccessfulHealthBoundaryBorrow(scenario.aboveCollateral, scenario.aboveHealth);
    }

    function _assertBorrowUsesConfiguredDecimalScales(
        uint128 borrowAmount_,
        uint128 collateralAmount_,
        uint256 expectedFee_,
        uint256 expectedHealth_
    ) internal {
        _configureFractionalPrices();
        _depositFractionalPriceCollateral(collateralAmount_);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            borrowAmount_,
            alice
        );

        assertEq(preview.resultingHealthFactor, expectedHealth_, "decimal-matrix health boundary");
        assertEq(preview.fee, expectedFee_, "preview fee in collateral-native units");

        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), borrowAmount_, alice, alice, preview.fee);

        assertTrue(preview.executable, "decimal-matrix preview executable");
        assertEq(borrowedOhm, borrowAmount_, "decimal-matrix borrowed OHM");
        assertEq(fee, preview.fee, "borrow fee matches preview collateral units");
        assertEq(fee, expectedFee_, "borrow fee in collateral-native units");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + expectedFee_,
            "treasury receives collateral-native fee"
        );
        assertEq(totalDebtOhm, borrowAmount_, "decimal-matrix debt");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "decimal-matrix preview debt");
        assertEq(maturity, preview.maturity, "decimal-matrix preview maturity");
        assertEq(ohm.balanceOf(alice), borrowAmount_, "decimal-matrix minted OHM");
        assertEq(healthFactor, preview.resultingHealthFactor, "decimal-matrix resulting health");
    }

    function _assertBorrowMatchesPreview(
        uint128 borrowAmount_,
        uint128 collateralAmount_
    ) internal {
        _configureFractionalPrices();
        _depositFractionalPriceCollateral(collateralAmount_);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            borrowAmount_,
            alice
        );
        assertTrue(preview.executable, "fuzzed preview executable");

        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), borrowAmount_, alice, alice, preview.fee);

        assertEq(borrowedOhm, borrowAmount_, "fuzzed borrowed OHM");
        assertEq(fee, preview.fee, "fuzzed preview fee");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + preview.fee,
            "fuzzed treasury fee"
        );
        assertEq(totalDebtOhm, borrowAmount_, "fuzzed debt");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "fuzzed preview debt");
        assertEq(maturity, preview.maturity, "fuzzed preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "fuzzed preview health");
    }

    function _configureFractionalPrices() internal {
        uint8 priceDecimals = _priceDecimals();
        uint256 priceScale = 10 ** priceDecimals;

        // $10.25 OHM and $0.75 collateral are exactly representable at 6 and 18 PRICE decimals.
        uint256 ohmUsdPrice = (41 * priceScale) / 4;
        uint256 collateralUsdPrice = (3 * priceScale) / 4;
        price.setPriceDecimals(priceDecimals);
        _configurePrice(address(ohm), ohmUsdPrice);
        _configurePrice(address(usds), collateralUsdPrice);
    }

    function _depositFractionalPriceCollateral(uint128 collateralAmount_) internal {
        // At the 1 bp LTV fuzz boundary, 100 OHM at $10.25 requires about 13.67 million
        // $0.75 collateral tokens, and its 25 bps fee is about 34,167 tokens.
        usds.mint(alice, collateralAmount_ + 100_000 * 10 ** _collateralDecimals());
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateralAmount_, alice);
        vm.stopPrank();
    }

    function _assertSuccessfulHealthBoundaryBorrow(
        uint128 collateralAmount_,
        uint256 expectedHealth_
    ) internal {
        _configureBoundaryPrices();
        _depositBoundaryCollateral(collateralAmount_);
        uint128 borrowAmount = uint128(100 * 10 ** _ohmDecimals());

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            borrowAmount,
            alice
        );
        assertEq(preview.resultingHealthFactor, expectedHealth_, "preview boundary health");

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), borrowAmount, alice, alice, preview.fee);

        assertTrue(preview.executable, "boundary preview executable");
        assertEq(borrowedOhm, borrowAmount, "boundary borrowed OHM");
        assertEq(fee, preview.fee, "boundary preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "boundary preview debt");
        assertEq(maturity, preview.maturity, "boundary preview maturity");
        assertEq(healthFactor, expectedHealth_, "borrow boundary health");
        assertEq(healthFactor, preview.resultingHealthFactor, "boundary preview health");
    }

    function _configureBoundaryPrices() internal {
        uint256 priceScale = 10 ** _priceDecimals();
        price.setPriceDecimals(_priceDecimals());
        _configurePrice(address(ohm), 10 * priceScale);
        _configurePrice(address(usds), priceScale);
    }

    function _depositBoundaryCollateral(uint128 collateralAmount_) internal {
        usds.mint(alice, collateralAmount_ + 100 * 10 ** _collateralDecimals());
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateralAmount_, alice);
        vm.stopPrank();
    }
}

contract BurnerLoansBorrowOhm6Collateral6Price18DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

contract BurnerLoansBorrowOhm18Collateral6Price18DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract BurnerLoansBorrowOhm6Collateral18Price18DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 18 decimals; collateral: 18 decimals.
        // For the fixed decimal-scale case, requiredUsd for 100 OHM at $10.25 and 85% LTV is
        // $1_205_882_352_941_176_470_589, so decimalScaleCollateral
        // = ceil(requiredUsd * 1e18 / $0.75e18) = 1_607_843_137_254_901_960_786.
        // Its USD value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(decimalScaleCollateral * 25 / 10_000)
        //                 = 4_019_607_843_137_254_902.
        // For one raw 6-decimal OHM unit, required collateral is 16_078_431_372_550, so its
        // rounded-up 25 bps fee is 40_196_078_432.
        // debtValueUsd = 100 OHM * $10e18 = $1_000e18.
        // launchRequiredUsd = ceil($1_000e18 * 10_000 / 8_500)
        //                   = $1_176_470_588_235_294_117_648.
        // At 100% LTV, requiredUsd = $1_000e18, so collateral = $1_000e18 * 1e18 / $1e18
        // = 1_000e18, and health = floor($1_000e18 * 1e18 / $1_000e18) = 1e18.
        // At $1e18 per collateral token, each collateral amount below is also its USD value.
        // belowCollateral = launchRequiredUsd - 1 = 1_176_470_588_235_294_117_647, so
        // belowHealth = floor(1_176_470_588_235_294_117_647 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_999_999_999.
        // minimumHealthyCollateral = launchRequiredUsd = 1_176_470_588_235_294_117_648, so
        // minimumHealthyHealth = floor(launchRequiredUsd * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = launchRequiredUsd + 1 = 1_176_470_588_235_294_117_649, so
        // aboveHealth = floor(1_176_470_588_235_294_117_649 * 1e18 / launchRequiredUsd)
        //             = 1e18 because the one-wei surplus is below WAD health precision.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_137_254_901_960_786,
                decimalScaleFee: 4_019_607_843_137_254_902,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e18,
                rawUnitFee: 40_196_078_432,
                exactHundredPercentLtvCollateral: 1_000e18,
                belowCollateral: 1_176_470_588_235_294_117_647,
                belowHealth: 999_999_999_999_999_999,
                minimumHealthyCollateral: 1_176_470_588_235_294_117_648,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_588_235_294_117_649,
                aboveHealth: 1e18
            });
    }
}

contract BurnerLoansBorrowOhm18Collateral18Price18DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 18 decimals; collateral: 18 decimals.
        // For the fixed decimal-scale case, requiredUsd for 100 OHM at $10.25 and 85% LTV is
        // $1_205_882_352_941_176_470_589, so decimalScaleCollateral
        // = ceil(requiredUsd * 1e18 / $0.75e18) = 1_607_843_137_254_901_960_786.
        // Its USD value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(decimalScaleCollateral * 25 / 10_000)
        //                 = 4_019_607_843_137_254_902.
        // For one raw 18-decimal OHM unit, required collateral is 18, so the rounded-up fee is 1.
        // debtValueUsd = 100 OHM * $10e18 = $1_000e18.
        // launchRequiredUsd = ceil($1_000e18 * 10_000 / 8_500)
        //                   = $1_176_470_588_235_294_117_648.
        // At 100% LTV, requiredUsd = $1_000e18, so collateral = $1_000e18 * 1e18 / $1e18
        // = 1_000e18, and health = floor($1_000e18 * 1e18 / $1_000e18) = 1e18.
        // At $1e18 per collateral token, each collateral amount below is also its USD value.
        // belowCollateral = launchRequiredUsd - 1 = 1_176_470_588_235_294_117_647, so
        // belowHealth = floor(1_176_470_588_235_294_117_647 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_999_999_999.
        // minimumHealthyCollateral = launchRequiredUsd = 1_176_470_588_235_294_117_648, so
        // minimumHealthyHealth = floor(launchRequiredUsd * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = launchRequiredUsd + 1 = 1_176_470_588_235_294_117_649, so
        // aboveHealth = floor(1_176_470_588_235_294_117_649 * 1e18 / launchRequiredUsd)
        //             = 1e18 because the one-wei surplus is below WAD health precision.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_137_254_901_960_786,
                decimalScaleFee: 4_019_607_843_137_254_902,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e18,
                rawUnitFee: 1,
                exactHundredPercentLtvCollateral: 1_000e18,
                belowCollateral: 1_176_470_588_235_294_117_647,
                belowHealth: 999_999_999_999_999_999,
                minimumHealthyCollateral: 1_176_470_588_235_294_117_648,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_588_235_294_117_649,
                aboveHealth: 1e18
            });
    }
}

contract BurnerLoansBorrowOhm6Collateral6Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 6 decimals; collateral: 6 decimals.
        // For the fixed decimal-scale case, debtValueUsd = 100 OHM * $10.25e6 = $1_025e6 and
        // requiredUsd = ceil($1_025e6 * 10_000 / 8_500) = $1_205_882_353.
        // decimalScaleCollateral = ceil(requiredUsd * 1e6 / $0.75e6) = 1_607_843_138.
        // Its USD value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(1_607_843_138 * 25 / 10_000) = 4_019_608.
        // For one raw 6-decimal OHM unit, required collateral is 18, so the rounded-up fee is 1.
        // debtValueUsd = 100 OHM * $10e6 = $1_000e6.
        // launchRequiredUsd = ceil($1_000e6 * 10_000 / 8_500) = $1_176_470_589.
        // At 100% LTV, requiredUsd = $1_000e6, so collateral = $1_000e6 * 1e6 / $1e6
        // = 1_000e6, and health = floor($1_000e6 * 1e18 / $1_000e6) = 1e18.
        // At $1e6 per collateral token, each collateral amount below is also its USD value.
        // belowCollateral = launchRequiredUsd - 1 = 1_176_470_588, so
        // belowHealth = floor(1_176_470_588 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_150_000_000.
        // minimumHealthyCollateral = launchRequiredUsd = 1_176_470_589, so
        // minimumHealthyHealth = floor(launchRequiredUsd * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = launchRequiredUsd + 1 = 1_176_470_590, so
        // aboveHealth = floor(1_176_470_590 * 1e18 / launchRequiredUsd)
        //             = 1_000_000_000_849_999_999.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_138,
                decimalScaleFee: 4_019_608,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e6,
                rawUnitFee: 1,
                exactHundredPercentLtvCollateral: 1_000e6,
                belowCollateral: 1_176_470_588,
                belowHealth: 999_999_999_150_000_000,
                minimumHealthyCollateral: 1_176_470_589,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_590,
                aboveHealth: 1_000_000_000_849_999_999
            });
    }
}

contract BurnerLoansBorrowOhm18Collateral6Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 6 decimals; collateral: 6 decimals.
        // For the fixed decimal-scale case, debtValueUsd = 100 OHM * $10.25e6 = $1_025e6 and
        // requiredUsd = ceil($1_025e6 * 10_000 / 8_500) = $1_205_882_353.
        // decimalScaleCollateral = ceil(requiredUsd * 1e6 / $0.75e6) = 1_607_843_138.
        // Its USD value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(1_607_843_138 * 25 / 10_000) = 4_019_608.
        // For one raw 18-decimal OHM unit, required collateral is 3, so the rounded-up fee is 1.
        // debtValueUsd = 100 OHM * $10e6 = $1_000e6.
        // launchRequiredUsd = ceil($1_000e6 * 10_000 / 8_500) = $1_176_470_589.
        // At 100% LTV, requiredUsd = $1_000e6, so collateral = $1_000e6 * 1e6 / $1e6
        // = 1_000e6, and health = floor($1_000e6 * 1e18 / $1_000e6) = 1e18.
        // At $1e6 per collateral token, each collateral amount below is also its USD value.
        // belowCollateral = launchRequiredUsd - 1 = 1_176_470_588, so
        // belowHealth = floor(1_176_470_588 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_150_000_000.
        // minimumHealthyCollateral = launchRequiredUsd = 1_176_470_589, so
        // minimumHealthyHealth = floor(launchRequiredUsd * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = launchRequiredUsd + 1 = 1_176_470_590, so
        // aboveHealth = floor(1_176_470_590 * 1e18 / launchRequiredUsd)
        //             = 1_000_000_000_849_999_999.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_138,
                decimalScaleFee: 4_019_608,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e6,
                rawUnitFee: 1,
                exactHundredPercentLtvCollateral: 1_000e6,
                belowCollateral: 1_176_470_588,
                belowHealth: 999_999_999_150_000_000,
                minimumHealthyCollateral: 1_176_470_589,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_590,
                aboveHealth: 1_000_000_000_849_999_999
            });
    }
}

contract BurnerLoansBorrowOhm6Collateral18Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 6 decimals; collateral: 18 decimals.
        // For the fixed decimal-scale case, requiredUsd for 100 OHM at $10.25 and 85% LTV is
        // $1_205_882_353, so decimalScaleCollateral
        // = ceil(requiredUsd * 1e18 / $0.75e6) = 1_607_843_137_333_333_333_334.
        // Its PRICE value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(decimalScaleCollateral * 25 / 10_000)
        //                 = 4_019_607_843_333_333_334.
        // For one raw 6-decimal OHM unit, required collateral is 17_333_333_333_334, so its
        // rounded-up fee is 43_333_333_334.
        // debtValueUsd = 100 OHM * $10e6 = $1_000e6.
        // launchRequiredUsd = ceil($1_000e6 * 10_000 / 8_500) = $1_176_470_589.
        // At 100% LTV, requiredUsd = $1_000e6, so collateral = $1_000e6 * 1e18 / $1e6
        // = 1_000e18. Its PRICE value is $1_000e6, giving health = 1e18.
        // minimumHealthyCollateral = launchRequiredUsd * 1e12 = 1_176_470_589e12.
        // belowCollateral = minimumHealthyCollateral - 1
        //                 = 1_176_470_588_999_999_999_999.
        // Its PRICE value is floor(belowCollateral * $1e6 / 1e18) = $1_176_470_588, so
        // belowHealth = floor($1_176_470_588 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_150_000_000.
        // The minimum converts to $1_176_470_589, so minimumHealthyHealth
        // = floor($1_176_470_589 * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = minimumHealthyCollateral + 1
        //                 = 1_176_470_589_000_000_000_001.
        // It still floors to $1_176_470_589 at PRICE precision, so aboveHealth remains 1e18.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_137_333_333_333_334,
                decimalScaleFee: 4_019_607_843_333_333_334,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e18,
                rawUnitFee: 43_333_333_334,
                exactHundredPercentLtvCollateral: 1_000e18,
                belowCollateral: 1_176_470_588_999_999_999_999,
                belowHealth: 999_999_999_150_000_000,
                minimumHealthyCollateral: 1_176_470_589e12,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_589_000_000_000_001,
                aboveHealth: 1e18
            });
    }

    // Condition tree:
    // - PRICE decimals: 6
    // - OHM decimals: 6
    // - Collateral decimals: 18
    // - OHM market price: $5 while the 18-decimal backing oracle reports $10 plus one wei
    // - Expected branch: scaled backing, preview fee, borrow fee, and treasury receipt use collateral units
    function test_givenSixPriceDecimals_borrowUsesScaledBackingAndCollateralFeeScale() public {
        price.setPriceDecimals(6);
        _configurePrice(address(ohm), 5e6);
        _configurePrice(address(usds), 1e6);
        backingOracle.setBacking(10e18 + 1);

        // Backing rounds up to $10.000001 at 6 PRICE decimals.
        // 100 OHM requires $1,000.0001 of backing; the 125% multiplier raises the collateral
        // requirement to 1,250.000125 USDS = 1_250_000_125e12 native units.
        uint128 collateralAmount = 1_250_000_125e12;
        usds.mint(alice, collateralAmount + 100e18);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateralAmount, alice);
        vm.stopPrank();

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            100e6,
            alice
        );
        uint256 treasuryBalanceBefore = usds.balanceOf(address(trsry));

        vm.prank(alice);
        (
            uint256 borrowedOhm,
            uint256 fee,
            uint256 totalDebtOhm,
            uint48 maturity,
            uint256 healthFactor
        ) = burnerLoans.borrow(address(usds), 100e6, alice, alice, preview.fee);

        // 1,250.000125 USDS * 25 bps = 3.1250003125 USDS in 18-decimal collateral units.
        uint256 expectedFee = 3_125_000_312_500_000_000;
        assertTrue(preview.executable, "scaled backing preview executable");
        assertEq(preview.resultingHealthFactor, 1e18, "scaled backing preview boundary");
        assertEq(borrowedOhm, 100e6, "scaled backing borrowed OHM");
        assertEq(healthFactor, 1e18, "scaled backing borrow boundary");
        assertEq(preview.fee, expectedFee, "preview fee in 18-decimal collateral units");
        assertEq(fee, expectedFee, "borrow fee in 18-decimal collateral units");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "scaled backing preview debt");
        assertEq(maturity, preview.maturity, "scaled backing preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "scaled backing preview health");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + expectedFee,
            "treasury receives 18-decimal collateral fee"
        );
    }
}

contract BurnerLoansBorrowOhm18Collateral18Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _launchBoundaryScenario()
        internal
        pure
        override
        returns (LaunchBoundaryScenario memory)
    {
        // PRICE: 6 decimals; collateral: 18 decimals.
        // For the fixed decimal-scale case, requiredUsd for 100 OHM at $10.25 and 85% LTV is
        // $1_205_882_353, so decimalScaleCollateral
        // = ceil(requiredUsd * 1e18 / $0.75e6) = 1_607_843_137_333_333_333_334.
        // Its PRICE value equals requiredUsd, so decimalScaleHealth = 1e18.
        // decimalScaleFee = ceil(decimalScaleCollateral * 25 / 10_000)
        //                 = 4_019_607_843_333_333_334.
        // For one raw 18-decimal OHM unit, required collateral is 2_666_666_666_667, so its
        // rounded-up fee is 6_666_666_667.
        // debtValueUsd = 100 OHM * $10e6 = $1_000e6.
        // launchRequiredUsd = ceil($1_000e6 * 10_000 / 8_500) = $1_176_470_589.
        // At 100% LTV, requiredUsd = $1_000e6, so collateral = $1_000e6 * 1e18 / $1e6
        // = 1_000e18. Its PRICE value is $1_000e6, giving health = 1e18.
        // minimumHealthyCollateral = launchRequiredUsd * 1e12 = 1_176_470_589e12.
        // belowCollateral = minimumHealthyCollateral - 1
        //                 = 1_176_470_588_999_999_999_999.
        // Its PRICE value is floor(belowCollateral * $1e6 / 1e18) = $1_176_470_588, so
        // belowHealth = floor($1_176_470_588 * 1e18 / launchRequiredUsd)
        //             = 999_999_999_150_000_000.
        // The minimum converts to $1_176_470_589, so minimumHealthyHealth
        // = floor($1_176_470_589 * 1e18 / launchRequiredUsd) = 1e18.
        // aboveCollateral = minimumHealthyCollateral + 1
        //                 = 1_176_470_589_000_000_000_001.
        // It still floors to $1_176_470_589 at PRICE precision, so aboveHealth remains 1e18.
        return
            LaunchBoundaryScenario({
                decimalScaleCollateral: 1_607_843_137_333_333_333_334,
                decimalScaleFee: 4_019_607_843_333_333_334,
                decimalScaleHealth: 1e18,
                fuzzCollateral: 20_000_000e18,
                rawUnitFee: 6_666_666_667,
                exactHundredPercentLtvCollateral: 1_000e18,
                belowCollateral: 1_176_470_588_999_999_999_999,
                belowHealth: 999_999_999_150_000_000,
                minimumHealthyCollateral: 1_176_470_589e12,
                minimumHealthyHealth: 1e18,
                aboveCollateral: 1_176_470_589_000_000_000_001,
                aboveHealth: 1e18
            });
    }
}

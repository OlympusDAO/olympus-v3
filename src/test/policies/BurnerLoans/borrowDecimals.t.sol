// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansBorrowTestBase} from "./fixtures/BurnerLoansBorrowTestBase.sol";

abstract contract BurnerLoansBorrowDecimalsTest is BurnerLoansBorrowTestBase {
    function _priceDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function _boundaryHealthExpectations()
        internal
        pure
        virtual
        returns (uint256 belowBoundary_, uint256 aboveBoundary_)
    {
        return (999_999_999_130_434_782, 1_000_000_000_869_565_217);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Borrow amount: fuzzed from one raw OHM unit through 100 whole OHM
    // - Prices: fractional values exercise scale conversion without whole-number shortcuts
    // - Expected branch: no intermediate value truncates to zero and all outputs use native scales
    function test_givenFuzzedBorrowAmount_borrowUsesConfiguredDecimalScales(
        uint128 borrowAmount_
    ) public {
        uint8 ohmDecimals = _ohmDecimals();
        uint256 ohmScale = 10 ** ohmDecimals;
        uint128 borrowAmount = uint128(bound(uint256(borrowAmount_), 1, 100 * ohmScale));

        _assertBorrowUsesConfiguredDecimalScales(borrowAmount);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Borrow amount: one smallest native OHM unit
    // - Expected branch: debt value, collateral requirement, and fee remain nonzero
    function test_givenOneRawOhmUnit_borrowDoesNotTruncateValuesToZero() public {
        _assertBorrowUsesConfiguredDecimalScales(1);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Collateral: exactly 1,150 units against a 1,150 USD requirement
    // - Expected branch: preview and borrow return exactly 1e18 health
    function test_givenExactHealthBoundary_borrowReturnsOneWad() public {
        _assertSuccessfulHealthBoundaryBorrow(uint128(1_150 * 10 ** _collateralDecimals()), 1e18);
    }

    // Condition tree:
    // - OHM, collateral, and PRICE decimals: supplied by the concrete matrix configuration
    // - Collateral: one smallest native unit below the exact 1,150-unit boundary
    // - Expected branch: preview and borrow revert with the exact rounded health factor
    function test_givenOneCollateralUnitBelowHealthBoundary_borrowReverts() public {
        _configureBoundaryPrices();
        uint8 collateralDecimals = _collateralDecimals();
        uint128 collateralAmount = uint128(1_150 * 10 ** collateralDecimals - 1);
        _depositBoundaryCollateral(collateralAmount);

        (uint256 expectedHealth, ) = _boundaryHealthExpectations();
        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_UnhealthyBorrow.selector,
            expectedHealth
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
    // - Collateral: one smallest native unit above the exact 1,150-unit boundary
    // - Expected branch: preview and borrow return the exact rounded health factor
    function test_givenOneCollateralUnitAboveHealthBoundary_borrowReturnsExpectedHealth() public {
        uint8 collateralDecimals = _collateralDecimals();
        (, uint256 expectedHealth) = _boundaryHealthExpectations();
        _assertSuccessfulHealthBoundaryBorrow(
            uint128(1_150 * 10 ** collateralDecimals + 1),
            expectedHealth
        );
    }

    function _assertBorrowUsesConfiguredDecimalScales(uint128 borrowAmount_) internal {
        uint8 collateralDecimals = _collateralDecimals();
        uint256 collateralScale = 10 ** collateralDecimals;
        uint128 collateralAmount = _configurePricesAndRequiredCollateral(borrowAmount_);

        usds.mint(alice, collateralAmount + 100 * collateralScale);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), type(uint256).max);
        burnerLoans.depositCollateral(address(usds), collateralAmount, alice);
        vm.stopPrank();

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            borrowAmount_,
            alice
        );

        // fee = ceil(collateralAmount * 25 bps / 10,000), token-native units.
        uint256 expectedFee = (collateralAmount * 25 + 9_999) / 10_000;
        assertGt(expectedFee, 0, "nonzero debt retains nonzero fee");
        assertGe(preview.resultingHealthFactor, 1e18, "decimal-matrix health boundary");
        assertEq(preview.fee, expectedFee, "preview fee in collateral-native units");

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
        assertEq(fee, expectedFee, "borrow fee in collateral-native units");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + expectedFee,
            "treasury receives collateral-native fee"
        );
        assertEq(totalDebtOhm, borrowAmount_, "decimal-matrix debt");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "decimal-matrix preview debt");
        assertEq(maturity, preview.maturity, "decimal-matrix preview maturity");
        assertEq(ohm.balanceOf(alice), borrowAmount_, "decimal-matrix minted OHM");
        assertEq(healthFactor, preview.resultingHealthFactor, "decimal-matrix resulting health");
    }

    function _configurePricesAndRequiredCollateral(
        uint128 borrowAmount_
    ) internal returns (uint128 collateralAmount) {
        uint8 ohmDecimals = _ohmDecimals();
        uint8 collateralDecimals = _collateralDecimals();
        uint8 priceDecimals = _priceDecimals();
        uint256 priceScale = 10 ** priceDecimals;

        // $10.25 OHM and $0.75 collateral are exactly representable at 6 and 18 PRICE decimals.
        uint256 ohmUsdPrice = (41 * priceScale) / 4;
        uint256 collateralUsdPrice = (3 * priceScale) / 4;
        price.setPriceDecimals(priceDecimals);
        _configurePrice(address(ohm), ohmUsdPrice);
        _configurePrice(address(usds), collateralUsdPrice);

        // debtValueUsd = ceil(borrowAmount * $10.25 / ohmScale), in PRICE-native USD units.
        uint256 debtValueUsd = burnerLoans.debtValueUsd(borrowAmount_, ohmUsdPrice, ohmDecimals);
        // requiredUsd = ceil(debtValueUsd * 115% / 100%), in PRICE-native USD units.
        uint256 requiredUsd = (debtValueUsd * 11_500 + 9_999) / 10_000;
        // collateralAmount = ceil(requiredUsd * collateral scale / $0.75), in native units.
        collateralAmount = uint128(
            burnerLoans.requiredCollateralAsset(requiredUsd, collateralUsdPrice, collateralDecimals)
        );

        assertGt(debtValueUsd, 0, "nonzero debt retains PRICE-native value");
        assertGt(requiredUsd, 0, "nonzero debt retains required USD value");
        assertGt(collateralAmount, 0, "nonzero debt retains collateral requirement");
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

    function _boundaryHealthExpectations()
        internal
        pure
        override
        returns (uint256 belowBoundary_, uint256 aboveBoundary_)
    {
        return (999_999_999_999_999_999, 1e18);
    }
}

contract BurnerLoansBorrowOhm18Collateral18Price18DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _boundaryHealthExpectations()
        internal
        pure
        override
        returns (uint256 belowBoundary_, uint256 aboveBoundary_)
    {
        return (999_999_999_999_999_999, 1e18);
    }
}

contract BurnerLoansBorrowOhm6Collateral6Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
    }
}

contract BurnerLoansBorrowOhm18Collateral6Price6DecimalsTest is BurnerLoansBorrowDecimalsTest {
    function _ohmDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _priceDecimals() internal pure override returns (uint8) {
        return 6;
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

    function _boundaryHealthExpectations()
        internal
        pure
        override
        returns (uint256 belowBoundary_, uint256 aboveBoundary_)
    {
        return (999_999_999_130_434_782, 1e18);
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
        // 100 OHM therefore requires 1,000.0001 USDS = 1_000_000_100e12 native units.
        uint128 collateralAmount = 1_000_000_100e12;
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

        // 1,000.0001 USDS * 25 bps = 2.50000025 USDS in 18-decimal collateral units.
        uint256 expectedFee = 2_500_000_250_000_000_000;
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

    function _boundaryHealthExpectations()
        internal
        pure
        override
        returns (uint256 belowBoundary_, uint256 aboveBoundary_)
    {
        return (999_999_999_130_434_782, 1e18);
    }
}

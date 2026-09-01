// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansPriceIntegrationTestBase} from "./fixtures/BurnerLoansPriceIntegrationTestBase.sol";

abstract contract BurnerLoansBorrowPriceIntegrationSharedTest is
    BurnerLoansPriceIntegrationTestBase
{
    function _exactBoundaryCollateral() internal pure virtual returns (uint128);

    function _launchBoundaryCollateral() internal pure virtual returns (uint128);

    function _launchBoundaryHealth() internal pure virtual returns (uint256);

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - Prices: OHM = $10 and USDS = $1 from current 8-decimal feeds
    // - Maximum LTV: 100%, making the market requirement exactly 1,000 USD
    // - Collateral: exactly 1,000 USDS in the concrete token's native decimals
    // - Expected branch: preview and write agree at exactly 1e18 health
    function test_givenProductionPriceAtExactHealthBoundary_borrowMatchesPreview() public {
        IBurnerLoans.AssetRiskConfigInput memory riskConfig = _defaultAssetRiskConfigInput();
        riskConfig.maxLtvBps = 10_000;
        vm.prank(admin);
        burnerLoansConfig.setAssetRiskConfig(address(usds), riskConfig);

        _borrowAndAssertExpectedHealth(_exactBoundaryCollateral(), 1e18);
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - Prices: OHM = $10 and USDS = $1 from current 8-decimal feeds
    // - Maximum LTV: launch value of 85%
    // - Collateral: fixed minimum healthy amount for the concrete token decimals
    // - Expected branch: preview and write agree at the fixed rounded health factor
    function test_givenProductionPriceAtLaunchMaximumLtv_borrowMatchesPreview() public {
        _borrowAndAssertExpectedHealth(_launchBoundaryCollateral(), _launchBoundaryHealth());
    }

    function _borrowAndAssertExpectedHealth(
        uint128 collateralAmount_,
        uint256 expectedHealth_
    ) internal {
        _depositCollateral(collateralAmount_);

        IBurnerLoans.BorrowPreview memory preview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
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
        ) = burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, preview.fee);

        assertTrue(preview.executable, "production PRICE preview executable");
        assertEq(
            preview.resultingHealthFactor,
            expectedHealth_,
            "production PRICE preview boundary health"
        );
        assertEq(borrowedOhm, _BORROW_AMOUNT, "production PRICE borrowed OHM");
        assertEq(fee, preview.fee, "production PRICE preview fee");
        assertEq(totalDebtOhm, preview.resultingDebtOhm, "production PRICE preview debt");
        assertEq(maturity, preview.maturity, "production PRICE preview maturity");
        assertEq(healthFactor, preview.resultingHealthFactor, "production PRICE preview health");
        assertEq(ohm.balanceOf(alice), _BORROW_AMOUNT, "production PRICE minted OHM");
        assertEq(
            usds.balanceOf(address(trsry)),
            treasuryBalanceBefore + preview.fee,
            "production PRICE treasury fee"
        );
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - OHM feed: older than its configured update threshold
    // - Expected branch: PRICE cannot resolve a nonzero current value and both quote and write revert
    function test_givenProductionPriceFeedIsStale_borrowReverts() public {
        _depositCollateral(_exactBoundaryCollateral());
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - OHM feed: zero answer
    // - Expected branch: PRICE cannot resolve a nonzero current value and both quote and write revert
    function test_givenProductionPriceFeedIsZero_borrowReverts() public {
        _depositCollateral(_exactBoundaryCollateral());
        _ohmUsdFeed.setLatestAnswer(0);

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
    }

    // Condition tree:
    // - PRICE dependency: production OlympusPricev2
    // - Collateral asset: removed from PRICE after Burner Loans configuration
    // - Expected branch: both quote and write propagate the unsupported-asset error
    function test_givenProductionPriceDoesNotSupportCollateral_borrowReverts() public {
        _depositCollateral(_exactBoundaryCollateral());
        vm.prank(_priceWriter);
        _productionPrice.removeAsset(address(usds));

        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_AssetNotApproved.selector,
            address(usds)
        );
        vm.expectRevert(error);
        burnerLoans.previewBorrow(address(usds), _BORROW_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert(error);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, type(uint256).max);
    }
}

contract BurnerLoansBorrowPriceIntegrationTest is BurnerLoansBorrowPriceIntegrationSharedTest {
    // debtValueUsd = 100e9 OHM * $10e18 / 1e9 = $1_000e18.
    // At 100% LTV: requiredUsd = $1_000e18 and exact collateral = 1_000e18.
    // At 85% LTV: requiredUsd = ceil($1_000e18 * 10_000 / 8_500)
    //                              = $1_176_470_588_235_294_117_648.
    // At a $1e18 collateral price, that value is 1_176_470_588_235_294_117_648 tokens.
    // Both collateral values divide exactly at 18 decimals, so boundary health is 1e18.
    function _collateralDecimals() internal pure override returns (uint8) {
        return 18;
    }

    function _exactBoundaryCollateral() internal pure override returns (uint128) {
        return 1_000e18;
    }

    function _launchBoundaryCollateral() internal pure override returns (uint128) {
        return 1_176_470_588_235_294_117_648;
    }

    function _launchBoundaryHealth() internal pure override returns (uint256) {
        return 1e18;
    }

    function _feeReserve() internal pure override returns (uint256) {
        return 100e18;
    }
}

contract BurnerLoansBorrowPriceIntegrationSixDecimalCollateralTest is
    BurnerLoansBorrowPriceIntegrationSharedTest
{
    // debtValueUsd = 100e9 OHM * $10e18 / 1e9 = $1_000e18.
    // At 100% LTV: exact collateral = $1_000e18 * 1e6 / $1e18 = 1_000e6.
    // At 85% LTV: requiredUsd = ceil($1_000e18 * 10_000 / 8_500)
    //                              = $1_176_470_588_235_294_117_648.
    // Minimum collateral = ceil(requiredUsd * 1e6 / $1e18) = 1_176_470_589.
    // Its USD value is $1_176_470_589e12, so health is
    // floor($1_176_470_589e12 * 1e18 / requiredUsd) = 1_000_000_000_649_999_999.
    function _collateralDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _exactBoundaryCollateral() internal pure override returns (uint128) {
        return 1_000e6;
    }

    function _launchBoundaryCollateral() internal pure override returns (uint128) {
        return 1_176_470_589;
    }

    function _launchBoundaryHealth() internal pure override returns (uint256) {
        return 1_000_000_000_649_999_999;
    }

    function _feeReserve() internal pure override returns (uint256) {
        return 100e6;
    }
}

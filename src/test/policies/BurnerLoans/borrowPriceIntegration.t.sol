// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansPriceIntegrationTestBase} from "./fixtures/BurnerLoansPriceIntegrationTestBase.sol";

contract BurnerLoansBorrowPriceIntegrationTest is BurnerLoansPriceIntegrationTestBase {
    // Condition tree:
    // - PRICE dependency: production OlympusPricev2 with ChainlinkPriceFeeds
    // - Prices: OHM = $10 and USDS = $1 from current 8-decimal feeds
    // - Collateral: exactly the 115% minimum collateral boundary
    // - Expected branch: preview and write agree and borrowing succeeds at exactly 1e18 health
    function test_givenProductionPriceAtExactHealthBoundary_borrowMatchesPreview() public {
        _depositExactBoundaryCollateral();

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
        assertEq(preview.resultingHealthFactor, 1e18, "production PRICE preview boundary health");
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
        _depositExactBoundaryCollateral();
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
        _depositExactBoundaryCollateral();
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
        _depositExactBoundaryCollateral();
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

    function _depositExactBoundaryCollateral() internal {
        _depositCollateral(_EXACT_BOUNDARY_COLLATERAL);
    }
}

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansPriceIntegrationTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansPriceIntegrationTestBase.sol";

contract BurnerLoansPriceIntegrationTest is BurnerLoansPriceIntegrationTestBase {
    uint128 internal constant _LIFECYCLE_COLLATERAL = 2_000e6;

    // integration
    // given supported production prices
    //  when the integration flow is executed
    //   then it drives borrow, withdraw, extend, and seize
    function test_supportedProductionPrices_driveBorrowWithdrawExtendAndSeize() public {
        backingOracle.setBacking(10e18);
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, borrowPreview.fee);

        vm.prank(alice);
        (, uint256 withdrawn, uint256 remaining, uint256 withdrawalHealth) = burnerLoans
            .withdrawCollateral(address(usds), 100e6, alice, alice);
        assertEq(withdrawn, 100e6, "withdrawn collateral");
        assertEq(remaining, 1_900e6, "remaining collateral");
        // Launch parameters: maxLtvBps = 8,500 and backingMultiplierBps = 12,500.
        // Debt = 100e9 OHM (9 decimals); backing = $10e18 per OHM (18 decimals).
        // Backing debt value = 100e9 * $10e18 / 1e9 = $1,000e18.
        // Backing requirement = $1,000e18 * 12,500 / 10,000 = $1,250e18.
        // OHM market price is $10e18, below the $10.625e18 crossover, so backing dominates.
        // Remaining collateral value = 1,900e6 * $1e18 / 1e6 = $1,900e18.
        // Health = floor($1,900e18 * 1e18 / $1,250e18) = 1.52e18 WAD.
        assertEq(withdrawalHealth, 1.52e18, "backing-dominant withdrawal health");

        IBurnerLoans.ExtendPreview memory extendPreview = burnerLoans.previewExtend(
            address(usds),
            alice,
            1
        );
        vm.prank(alice);
        (uint256 extensionFee, uint48 maturity, uint256 extensionHealth) = burnerLoans.extend(
            address(usds),
            alice,
            1,
            extendPreview.fee
        );
        assertEq(extensionFee, extendPreview.fee, "extension fee");
        assertEq(maturity, extendPreview.maturity, "extension maturity");
        assertEq(extensionHealth, extendPreview.healthFactor, "extension health");

        _ohmUsdFeed.setLatestAnswer(20e8);
        _ohmUsdFeed.setTimestamp(block.timestamp);
        assertTrue(burnerLoans.isSeizable(address(usds), alice), "position seizable");

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        burnerLoans.seize(address(usds), borrowers);

        IBurnerLoans.Position memory position = burnerLoans.getPosition(address(usds), alice);
        assertEq(position.debtOhm, 0, "seized debt");
        assertEq(position.depositedCollateral, 0, "seized collateral");
        assertEq(burnerLoans.totalActiveDebtOhm(), 0, "active debt after seizure");
        assertEq(
            floan.getMarketPrincipalDefaulted(burnerLoansConfig.marketId(address(usds))),
            _BORROW_AMOUNT,
            "defaulted principal"
        );
    }

    // integration
    // given stale production price
    //  when the integration flow is executed
    //   then it blocks risk actions and rolls back
    function test_staleProductionPrice_blocksRiskActionsAndRollsBack() public {
        _depositCollateral(_LIFECYCLE_COLLATERAL);
        IBurnerLoans.BorrowPreview memory borrowPreview = burnerLoans.previewBorrow(
            address(usds),
            _BORROW_AMOUNT,
            alice
        );
        vm.prank(alice);
        burnerLoans.borrow(address(usds), _BORROW_AMOUNT, alice, alice, borrowPreview.fee);
        IBurnerLoans.Position memory beforePosition = burnerLoans.getPosition(address(usds), alice);
        _ohmUsdFeed.setTimestamp(block.timestamp - _FEED_UPDATE_THRESHOLD - 1);
        bytes memory error = abi.encodeWithSelector(
            IPRICEv2.PRICE_PriceZero.selector,
            address(ohm)
        );

        vm.expectRevert(error);
        vm.prank(alice);
        burnerLoans.withdrawCollateral(address(usds), 1e6, alice, alice);

        vm.expectRevert(error);
        vm.prank(alice);
        burnerLoans.extend(address(usds), alice, 1, type(uint256).max);

        address[] memory borrowers = new address[](1);
        borrowers[0] = alice;
        vm.expectRevert(error);
        burnerLoans.seize(address(usds), borrowers);

        IBurnerLoans.Position memory afterPosition = burnerLoans.getPosition(address(usds), alice);
        assertEq(
            afterPosition.depositedCollateral,
            beforePosition.depositedCollateral,
            "collateral"
        );
        assertEq(afterPosition.debtOhm, beforePosition.debtOhm, "debt");
        assertEq(afterPosition.maturity, beforePosition.maturity, "maturity");
        assertEq(burnerLoans.totalActiveDebtOhm(), _BORROW_AMOUNT, "active debt");
    }
}

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansHarvestTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarvestTestBase.sol";

contract BurnerLoansGetAssetCollateralStatusTest is BurnerLoansHarvestTestBase {
    // getAssetCollateralStatus
    // given configured vault custody with borrower principal and earned yield
    //  when reading collateral status
    //   then every field reconciles to DepositManager accounting
    function test_givenSurplus_returnsDepositManagerAccounting() public {
        _depositCollateral();
        _addYield(10e6);

        (uint256 expectedShares, uint256 expectedAssets) = depositManager.getOperatorAssets(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        uint256 expectedBorrowed = depositManager.getBorrowedAmount(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        uint256 expectedLiabilities = depositManager.getOperatorLiabilities(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        uint256 expectedYield = depositManager.maxClaimYield(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );

        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(vaultAsset)
        );

        assertEq(status.shares, expectedShares, "shares");
        assertEq(status.assets, expectedAssets, "assets");
        assertEq(status.borrowed, expectedBorrowed, "borrowed");
        assertEq(status.liabilities, expectedLiabilities, "liabilities");
        assertEq(status.claimableYield, expectedYield, "claimable yield");
        assertTrue(status.solvent, "solvent");
    }

    // getAssetCollateralStatus
    // given custody assets fall below borrower liabilities
    //  when reading collateral status
    //   then the shortfall is surfaced without reverting
    function test_givenCustodyShortfall_reportsInsolvent() public {
        _depositCollateral();
        _causeShortfall(1);

        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(vaultAsset)
        );

        assertEq(status.assets, _COLLATERAL_AMOUNT - 1, "assets");
        assertEq(status.liabilities, _COLLATERAL_AMOUNT, "liabilities");
        assertEq(status.claimableYield, 0, "claimable yield");
        assertFalse(status.solvent, "solvent");
    }

    // getAssetCollateralStatus
    // given FLOAN has two matching markets for this facility and token pair
    //  when reading collateral status
    //   then Burner Loans rejects the ambiguous asset namespace
    function test_givenMultipleMatchingMarkets_reverts() public {
        _createDuplicateMarketForTest(address(vaultAsset));

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_AmbiguousMarket.selector,
                address(vaultAsset),
                2
            )
        );
        burnerLoans.getAssetCollateralStatus(address(vaultAsset));
    }
}

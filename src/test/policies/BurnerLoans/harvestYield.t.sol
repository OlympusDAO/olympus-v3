// SPDX-License-Identifier: Unlicense
// solhint-disable one-contract-per-file
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";

import {BurnerLoansHarvestTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarvestTestBase.sol";

contract BurnerLoansHarvestYieldTest is BurnerLoansHarvestTestBase {
    // harvestYield
    // given configured vault custody with borrower principal and earned yield
    //  when any keeper harvests
    //   then DepositManager sends its executable rounded amount to TRSRY
    function test_givenSurplus_transfersQuoteToTreasury() public {
        _depositCollateral();
        _addYield(10e6);
        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );
        (uint256 expectedShares, uint256 expectedAssets) = depositManager.getOperatorAssets(
            IERC20(address(vaultAsset)),
            address(burnerLoans)
        );
        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(vaultAsset)
        );
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

        assertEq(status.shares, expectedShares, "shares before harvest");
        assertEq(status.assets, expectedAssets, "assets before harvest");
        assertEq(
            status.borrowed,
            depositManager.getBorrowedAmount(IERC20(address(vaultAsset)), address(burnerLoans)),
            "borrowed before harvest"
        );
        assertEq(status.liabilities, _COLLATERAL_AMOUNT, "liabilities before harvest");
        assertEq(status.claimableYield, preview.amount, "claimable yield matches preview");
        assertTrue(status.solvent, "solvent before harvest");

        vm.expectEmit(true, false, false, false, address(burnerLoans));
        emit IBurnerLoans.YieldHarvested(address(vaultAsset), 0);
        uint256 claimed = burnerLoans.harvestYield(address(vaultAsset));

        assertGt(claimed, 0, "claimed yield");
        assertLe(claimed, preview.amount, "claim within theoretical maximum");
        assertEq(vaultAsset.balanceOf(address(trsry)), treasuryBefore + claimed, "treasury yield");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "policy residual");
    }

    // harvestYield
    // given a borrower position and earned custody yield
    //  when yield is harvested
    //   then borrower state and health remain unchanged
    function test_givenBorrowerPosition_doesNotChangeBorrowerAccounting() public {
        _depositCollateral();
        _addYield(10e6);
        IBurnerLoans.Position memory positionBefore = burnerLoans.getPosition(
            address(vaultAsset),
            alice
        );
        uint256 healthBefore = burnerLoans.positionHealthFactor(
            address(vaultAsset),
            positionBefore.depositedCollateral,
            positionBefore.debtOhm
        );

        burnerLoans.harvestYield(address(vaultAsset));

        _assertPositionEq(burnerLoans.getPosition(address(vaultAsset), alice), positionBefore);
        assertEq(
            burnerLoans.positionHealthFactor(
                address(vaultAsset),
                positionBefore.depositedCollateral,
                positionBefore.debtOhm
            ),
            healthBefore,
            "health factor"
        );
    }

    // harvestYield
    // given configured custody without earned yield
    //  when harvest is called
    //   then it succeeds as an idempotent no-op
    function test_givenNoSurplus_returnsZero() public {
        _depositCollateral();

        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );
        uint256 claimed = burnerLoans.harvestYield(address(vaultAsset));

        assertEq(preview.amount, 0, "preview claimable yield");
        assertTrue(preview.executable, "preview executable");
        assertEq(claimed, 0, "claimed yield");
        assertEq(vaultAsset.balanceOf(address(trsry)), 0, "treasury yield");
    }

    // harvestYield
    // given the collateral market is disabled after earning yield
    //  when harvest is called
    //   then safe accounting cleanup remains available
    function test_givenAssetOriginationsDisabled_stillHarvests() public {
        _depositCollateral();
        _addYield(10e6);
        vm.prank(admin);
        burnerLoansConfig.setAssetOriginationsEnabled(address(vaultAsset), false);

        uint256 claimed = burnerLoans.harvestYield(address(vaultAsset));

        assertGt(claimed, 0, "claimed yield");
        assertEq(vaultAsset.balanceOf(address(trsry)), claimed, "treasury yield");
    }

    // harvestYield
    // given the policy is globally disabled
    //  when harvest is called
    //   then the emergency pause blocks the external interaction
    function test_givenPolicyDisabled_reverts() public {
        _depositCollateral();
        _addYield(10e6);
        vm.prank(emergency);
        burnerLoans.disable("");

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.previewHarvestYield(address(vaultAsset));

        vm.expectRevert(IEnabler.NotEnabled.selector);
        burnerLoans.harvestYield(address(vaultAsset));
    }

    // harvestYield
    // given custody assets fall below liabilities
    //  when harvest is called
    //   then the shortfall blocks any custody withdrawal
    function test_givenCustodyShortfall_reverts() public {
        _depositCollateral();
        _causeShortfall(1);

        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(vaultAsset)
        );
        assertEq(status.assets, _COLLATERAL_AMOUNT - 1, "shortfall assets");
        assertEq(status.liabilities, _COLLATERAL_AMOUNT, "shortfall liabilities");
        assertEq(status.claimableYield, 0, "shortfall claimable yield");
        assertFalse(status.solvent, "shortfall solvency");

        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );
        assertEq(preview.amount, 0, "preview claimable yield");
        assertFalse(preview.executable, "preview executable");

        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnerLoans.BurnerLoans_CustodyShortfall.selector,
                address(vaultAsset),
                _COLLATERAL_AMOUNT,
                _COLLATERAL_AMOUNT - 1,
                0
            )
        );
        burnerLoans.harvestYield(address(vaultAsset));
    }

    // harvestYield
    // given a DepositManager callback attempts to harvest the same asset again
    //  when the outer harvest claims yield
    //   then the callback is rejected and yield is claimed only once
    function test_givenReentrantDepositManager_claimsOnlyOnce() public {
        _useMockDepositManager();
        uint128 collateral = 100e6;
        uint256 yield = 1e6;
        usds.mint(alice, collateral);
        vm.startPrank(alice);
        usds.approve(address(burnerLoans), collateral);
        burnerLoans.depositCollateral(address(usds), collateral, alice);
        vm.stopPrank();
        usds.mint(address(mockDepositManager), yield);
        mockDepositManager.setClaimableYield(yield);
        mockDepositManager.setClaimYieldCallback(
            address(burnerLoans),
            abi.encodeCall(burnerLoans.harvestYield, (address(usds)))
        );

        uint256 claimed = burnerLoans.harvestYield(address(usds));

        assertEq(claimed, yield, "claimed yield");
        assertEq(mockDepositManager.claimYieldCalls(), 1, "claim calls");
        assertFalse(mockDepositManager.claimYieldCallbackSucceeded(), "callback succeeded");
        assertEq(usds.balanceOf(address(trsry)), yield, "treasury yield");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            collateral,
            "borrower collateral"
        );
    }

    // harvestYield
    // given FLOAN has two matching markets for this facility and token pair
    //  when custody status, preview, and harvest are called
    //   then Burner Loans uses the first market
    function test_givenMultipleMatchingMarkets_usesFirstMarket() public {
        _depositCollateral();
        _addYield(10e6);
        uint32 duplicateMarketId = _createDuplicateMarketForTest(address(vaultAsset));
        vm.prank(address(burnerLoansConfig));
        floan.setMarketConfigData(duplicateMarketId, hex"01");

        IBurnerLoans.AssetCollateralStatus memory status = burnerLoans.getAssetCollateralStatus(
            address(vaultAsset)
        );
        IBurnerLoans.HarvestPreview memory preview = burnerLoans.previewHarvestYield(
            address(vaultAsset)
        );
        uint256 claimed = burnerLoans.harvestYield(address(vaultAsset));

        assertEq(status.liabilities, _COLLATERAL_AMOUNT, "first-market liabilities");
        assertGt(preview.amount, 0, "preview yield");
        assertGt(claimed, 0, "claimed yield");
        assertEq(vaultAsset.balanceOf(address(trsry)), claimed, "treasury yield");
    }

    // harvestYield
    // given the asset has no Burner Loans market
    //  when previewing or executing harvest
    //   then both paths reject the asset namespace
    function test_givenAssetNotConfigured_reverts() public {
        address unconfiguredAsset = makeAddr("unconfiguredAsset");

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_AssetNotConfigured.selector,
            unconfiguredAsset
        );

        vm.expectRevert(error);
        burnerLoans.previewHarvestYield(unconfiguredAsset);

        vm.expectRevert(error);
        burnerLoans.harvestYield(unconfiguredAsset);
    }

    // harvestYield
    // given DepositManager is disabled
    //  when previewing or executing harvest
    //   then both paths reject the disabled custody dependency
    function test_givenDepositManagerDisabled_reverts() public {
        vm.prank(admin);
        depositManager.disable("");

        bytes memory error = abi.encodeWithSelector(
            IBurnerLoans.BurnerLoans_InvalidDepositManager.selector,
            address(depositManager)
        );

        vm.expectRevert(error);
        burnerLoans.previewHarvestYield(address(vaultAsset));

        vm.expectRevert(error);
        burnerLoans.harvestYield(address(vaultAsset));
    }
}

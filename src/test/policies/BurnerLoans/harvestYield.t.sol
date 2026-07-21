// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

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
        uint256 treasuryBefore = vaultAsset.balanceOf(address(trsry));

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

        uint256 claimed = burnerLoans.harvestYield(address(vaultAsset));

        assertEq(claimed, 0, "claimed yield");
        assertEq(vaultAsset.balanceOf(address(trsry)), 0, "treasury yield");
    }

    // harvestYield
    // given the collateral market is disabled after earning yield
    //  when harvest is called
    //   then safe accounting cleanup remains available
    function test_givenAssetDisabled_stillHarvests() public {
        _depositCollateral();
        _addYield(10e6);
        vm.prank(admin);
        burnerLoans.disableAsset(address(vaultAsset));

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
        burnerLoans.harvestYield(address(vaultAsset));
    }

    // harvestYield
    // given custody assets fall below liabilities
    //  when harvest is called
    //   then the shortfall blocks any custody withdrawal
    function test_givenCustodyShortfall_reverts() public {
        _depositCollateral();
        _causeShortfall(1);

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
    //  when harvest is called
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
        burnerLoans.harvestYield(address(vaultAsset));
    }
}

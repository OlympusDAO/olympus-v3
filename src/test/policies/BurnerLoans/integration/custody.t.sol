// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {BurnerLoansHarvestTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarvestTestBase.sol";

contract BurnerLoansCustodyIntegrationTest is BurnerLoansHarvestTestBase {
    // given real DepositManager vault custody receives borrower principal and earns yield
    //  when yield is harvested and all credited collateral is withdrawn
    //   then accounting reconciles and BurnerLoans retains no underlying or vault shares
    function test_depositHarvestWithdraw_reconcilesCustodyWithoutPolicyResiduals() public {
        _depositCollateral();
        IBurnerLoans.AssetCollateralStatus memory depositedStatus = burnerLoans
            .getAssetCollateralStatus(address(vaultAsset));
        assertEq(depositedStatus.liabilities, _COLLATERAL_AMOUNT, "deposit liabilities");
        assertEq(depositedStatus.assets, _COLLATERAL_AMOUNT, "deposit assets");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "deposit asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "deposit vault residual");

        _addYield(10e6);
        uint256 harvested = burnerLoans.harvestYield(address(vaultAsset));
        assertGt(harvested, 0, "harvested yield");
        assertEq(vaultAsset.balanceOf(address(trsry)), harvested, "treasury yield");
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "harvest asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "harvest vault residual");

        vm.prank(alice);
        (, uint256 withdrawn, uint256 remaining, ) = burnerLoans.withdrawCollateral(
            address(vaultAsset),
            _COLLATERAL_AMOUNT,
            alice,
            alice
        );
        assertGt(withdrawn, 0, "withdrawn assets");
        assertEq(remaining, 0, "remaining collateral");
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            0,
            "withdraw liabilities"
        );
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(vaultAsset.balanceOf(address(burnerLoans)), 0, "withdraw asset residual");
        assertEq(vault.balanceOf(address(burnerLoans)), 0, "withdraw vault residual");
    }
}

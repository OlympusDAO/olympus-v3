// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {IERC20} from "src/interfaces/IERC20.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";
import {BurnerLoansHarvestTestBase} from "src/test/policies/BurnerLoans/fixtures/BurnerLoansHarvestTestBase.sol";

contract BurnerLoansCustodyIntegrationTest is BurnerLoansHarvestTestBase {
    // integration
    // given configuration and receipt identity
    //  when the integration flow is executed
    //   then it matches Burner Loans custody
    function test_configurationAndReceiptIdentity_matchBurnerLoansCustody() public {
        IDepositManager.AssetPeriodStatus memory period = depositManager.isAssetPeriod(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertTrue(period.isConfigured, "asset period configured");
        assertTrue(period.isEnabled, "asset period enabled");
        assertEq(depositManager.getOperatorName(address(burnerLoans)), "brn", "operator name");
        assertTrue(
            roles.hasRole(address(burnerLoans), depositManager.ROLE_DEPOSIT_OPERATOR()),
            "deposit operator role"
        );

        _depositCollateral();
        (uint256 receiptTokenId, address wrappedToken) = depositManager.getReceiptToken(
            IERC20(address(vaultAsset)),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(burnerLoans)
        );
        assertNotEq(receiptTokenId, 0, "receipt token id");
        assertNotEq(wrappedToken, address(0), "wrapped receipt token");
        assertEq(
            receiptTokenManager.balanceOf(address(burnerLoans), receiptTokenId),
            _COLLATERAL_AMOUNT,
            "receipt token balance"
        );
    }

    // integration
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

    // integration
    // given deposit manager role failure
    //  when the integration flow is executed
    //   then it rolls back burner loans deposit
    function test_depositManagerRoleFailure_rollsBackBurnerLoansDeposit() public {
        vaultAsset.mint(alice, _COLLATERAL_AMOUNT);
        vm.prank(alice);
        vaultAsset.approve(address(burnerLoans), _COLLATERAL_AMOUNT);
        bytes32 depositOperatorRole = depositManager.ROLE_DEPOSIT_OPERATOR();
        vm.prank(admin);
        rolesAdmin.revokeRole(depositOperatorRole, address(burnerLoans));

        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, depositOperatorRole)
        );
        vm.prank(alice);
        burnerLoans.depositCollateral(address(vaultAsset), _COLLATERAL_AMOUNT, alice);

        assertEq(vaultAsset.balanceOf(alice), _COLLATERAL_AMOUNT, "caller collateral restored");
        assertEq(
            burnerLoans.getPosition(address(vaultAsset), alice).depositedCollateral,
            0,
            "position collateral"
        );
        assertEq(
            depositManager.getOperatorLiabilities(
                IERC20(address(vaultAsset)),
                address(burnerLoans)
            ),
            0,
            "operator liabilities"
        );
    }
}

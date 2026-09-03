// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {stdError} from "forge-std/StdError.sol";

import {IBurnerLoansComposites} from "src/periphery/interfaces/IBurnerLoansComposites.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";
import {BurnerLoansCompositesTest} from "src/test/periphery/BurnerLoansComposites/BurnerLoansCompositesTest.sol";

contract BurnerLoansCompositesRepayAndWithdrawTest is BurnerLoansCompositesTest {
    function _repayParams(
        uint128 maxRepayOhm_,
        uint128 collateralAmount_,
        address recipient_
    ) internal view returns (IBurnerLoansComposites.RepayAndWithdrawParams memory) {
        return
            IBurnerLoansComposites.RepayAndWithdrawParams({
                asset: address(usds),
                maxRepayOhm: maxRepayOhm_,
                collateralAmount: collateralAmount_,
                recipient: recipient_
            });
    }

    // repayAndWithdraw
    // given an authorized caller has active debt and healthy collateral after the requested exit
    //  when repaying and withdrawing
    //   then debt and collateral decrease atomically and output routes to the recipient
    function test_givenHealthyResult_repaysAndWithdraws() public {
        _openPosition();
        uint128 repayAmount = 50e9;
        uint128 withdrawAmount = 500e6;
        vm.prank(alice);
        ohm.approve(address(composites), repayAmount);

        vm.prank(alice);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(repayAmount, withdrawAmount, recipient)
        );

        assertEq(result.repaidOhm, repayAmount, "repaid OHM");
        assertEq(result.refundedOhm, 0, "refunded OHM");
        assertEq(result.tokenOut, address(usds), "token out");
        assertEq(result.amountOut, withdrawAmount, "amount out");
        assertEq(result.remainingCollateral, _COLLATERAL - withdrawAmount, "remaining collateral");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            _BORROW - repayAmount,
            "debt"
        );
        assertEq(usds.balanceOf(recipient), withdrawAmount, "recipient collateral");
        _assertCompositeBalances(address(usds));
    }

    // repayAndWithdraw
    // given the caller supplies more OHM than the outstanding debt
    //  when repaying and withdrawing all collateral
    //   then only outstanding debt is repaid and excess OHM is refunded
    function test_givenMaxRepayAboveDebt_refundsExcess() public {
        _openPosition();
        uint128 maxRepay = 150e9;
        ohm.mint(alice, maxRepay - _BORROW);
        vm.prank(alice);
        ohm.approve(address(composites), maxRepay);

        vm.prank(alice);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(maxRepay, _COLLATERAL, alice)
        );

        assertEq(result.repaidOhm, _BORROW, "repaid OHM");
        assertEq(result.refundedOhm, maxRepay - _BORROW, "refunded OHM");
        assertEq(ohm.balanceOf(alice), maxRepay - _BORROW, "caller OHM refund");
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, 0, "position debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            0,
            "position collateral"
        );
        _assertCompositeBalances(address(usds));
    }

    // repayAndWithdraw
    // given the caller has active debt
    //  when repaying partially without withdrawing collateral
    //   then the repayment health sentinel is preserved
    function test_givenActiveDebt_whenRepayingPartially_whenCollateralAmountIsZero() public {
        _openPosition();
        uint128 repayAmount = 40e9;
        vm.prank(alice);
        ohm.approve(address(composites), repayAmount);

        vm.prank(alice);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(repayAmount, 0, alice)
        );

        assertEq(result.repaidOhm, repayAmount, "repaid OHM");
        assertEq(result.refundedOhm, 0, "refunded OHM");
        assertEq(result.remainingCollateral, _COLLATERAL, "remaining collateral");
        assertEq(result.healthFactor, 0, "unknown health sentinel");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).debtOhm,
            _BORROW - repayAmount,
            "remaining debt"
        );
        _assertCompositeBalances(address(usds));
    }

    // repayAndWithdraw
    // given the caller has a debt-free position
    //  when maximum repayment is non-zero and collateral withdrawal is zero
    //   then the input is refunded and the debt-free health factor is returned
    function test_givenDebtFreePosition_whenMaxRepayIsNonZero_whenCollateralAmountIsZero() public {
        _openPosition();
        vm.startPrank(alice);
        ohm.approve(address(burnerLoans), _BORROW);
        burnerLoans.repay(address(usds), _BORROW, alice);
        ohm.approve(address(composites), 1);
        vm.stopPrank();
        ohm.mint(alice, 1);

        vm.prank(alice);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(1, 0, alice)
        );

        assertEq(result.repaidOhm, 0, "repaid OHM");
        assertEq(result.refundedOhm, 1, "refunded OHM");
        assertEq(result.remainingCollateral, _COLLATERAL, "remaining collateral");
        assertEq(result.healthFactor, type(uint256).max, "debt-free health factor");
        assertEq(ohm.balanceOf(alice), 1, "caller OHM refund");
        _assertCompositeBalances(address(usds));
    }

    // repayAndWithdraw
    // given the composite is not authorized to withdraw for the caller
    //  when repayment and withdrawal are requested together
    //   then the withdrawal revert rolls back the preceding repayment and token pull
    function test_givenNoAuthorization_revertsAndRollsBack() public {
        _openPosition();
        vm.prank(alice);
        burnerLoans.cancelAuthorization(address(composites));
        uint128 repayAmount = 50e9;
        vm.prank(alice);
        ohm.approve(address(composites), repayAmount);

        vm.expectRevert(IOperatorAuth.OperatorAuth_UnauthorizedOnBehalfOf.selector);
        vm.prank(alice);
        composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(repayAmount, 100e6, alice)
        );

        assertEq(ohm.balanceOf(alice), _BORROW, "caller OHM");
        assertEq(burnerLoans.getPosition(address(usds), alice).debtOhm, _BORROW, "position debt");
        assertEq(
            burnerLoans.getPosition(address(usds), alice).depositedCollateral,
            _COLLATERAL,
            "position collateral"
        );
        _assertCompositeBalances(address(usds));
    }

    // repayAndWithdraw
    // given the caller has not approved OHM input
    //  when repaying and withdrawing
    //   then the transfer fails before debt or collateral changes
    function test_givenMissingOhmApproval_reverts() public {
        _openPosition();

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(alice);
        composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(50e9, 100e6, alice)
        );
    }

    // repayAndWithdraw
    // given collateral itself is a whitelisted vault token held directly by DepositManager
    //  when debt is fully repaid and collateral withdrawn
    //   then the vault token is routed directly to the requested recipient
    function test_givenVaultTokenCollateral_routesVaultTokenOutput() public {
        MockERC20 vaultToken = new MockERC20("Vault Token", "vTOKEN", 18);
        _configurePrice(address(vaultToken), 1e18);
        _configureDepositManagerAsset(address(vaultToken));
        vm.prank(admin);
        burnerLoansConfig.addAsset(
            address(vaultToken),
            _defaultAssetDebtCap(),
            _defaultAssetRiskConfigInput(),
            _defaultAssetFeeConfig()
        );
        _authorize(alice);
        uint128 collateral = 2_000e18;
        uint256 maxFee = 10e18;
        vaultToken.mint(alice, collateral + maxFee);
        vm.prank(alice);
        vaultToken.approve(address(composites), collateral + maxFee);
        IBurnerLoansComposites.DepositAndBorrowParams memory depositParams = IBurnerLoansComposites
            .DepositAndBorrowParams({
                asset: address(vaultToken),
                collateralAmount: collateral,
                ohmAmount: _BORROW,
                recipient: alice,
                maxFee: maxFee
            });
        vm.prank(alice);
        composites.depositAndBorrow(_emptyAuthorization(), _emptySignature(), depositParams);
        vm.roll(block.number + 1);
        vm.prank(alice);
        ohm.approve(address(composites), _BORROW);
        IBurnerLoansComposites.RepayAndWithdrawParams memory repayParams = IBurnerLoansComposites
            .RepayAndWithdrawParams({
                asset: address(vaultToken),
                maxRepayOhm: _BORROW,
                collateralAmount: collateral,
                recipient: recipient
            });

        vm.prank(alice);
        IBurnerLoansComposites.RepayAndWithdrawResult memory result = composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            repayParams
        );

        assertEq(result.tokenOut, address(vaultToken), "token out");
        assertEq(vaultToken.balanceOf(recipient), collateral, "recipient vault token");
        _assertCompositeBalances(address(vaultToken));
    }

    // repayAndWithdraw
    // given both repay and withdrawal amounts are zero
    //  when calling the composite
    //   then the meaningless operation is rejected
    function test_givenZeroAmounts_reverts() public {
        vm.expectRevert(IBurnerLoansComposites.BurnerLoansComposites_ZeroAmount.selector);
        vm.prank(alice);
        composites.repayAndWithdraw(
            _emptyAuthorization(),
            _emptySignature(),
            _repayParams(0, 0, alice)
        );
    }
}

// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";

contract OnRepayCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the user has not approved spending of debt token
    //  [X] it reverts
    // given the user does not have enough debt token
    //  [X] it reverts
    // given the Clearinghouse is not enabled
    //  [X] it succeeds
    // given the payment is less than the interest due
    //  [X] principal receivables are not decremented
    //  [X] interest receivables are decremented by the payment amount
    //  [X] the debt token is transferred from the user to the Clearinghouse
    //  [X] no collateral is transferred from the clearinghouse to the user
    //  [X] no debt is repaid on CDEPO
    //  [X] the yield is swept to the TRSRY
    // [X] principal receivables are decremented
    // [X] interest receivables are decremented
    // [X] the debt token is transferred from the user to the Clearinghouse
    // [X] the collateral is transferred from the Clearinghouse to the user
    // [X] the debt is repaid on CDEPO
    // [X] the yield is swept to the TRSRY

    function test_spendingNotApproved_reverts()
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        cooler.repayLoan(0, 1e18);
    }

    function test_notEnoughDebt_reverts()
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToCooler(2e18)
    {
        // Move debt elsewhere
        vm.startPrank(USER);
        vault.transfer(OTHERS, vault.balanceOf(USER));
        vm.stopPrank();

        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        cooler.repayLoan(0, 1e18);
    }

    function test_repayInterest(
        uint256 amount_
    )
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToCooler(2e18)
    {
        // Determine the amount to repay
        ICooler.Loan memory loan = cooler.getLoan(0);
        uint256 repaymentAmount = loan.interestDue;
        uint256 amount = bound(amount_, 1, repaymentAmount);

        // Ensure the user has enough debt tokens
        vm.prank(address(TRSRY));
        vault.transfer(USER, amount);

        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER);
        uint256 expectedUserDebtTokenBalance = vault.balanceOf(USER) - amount;
        uint256 expectedCDEPODebtTokenBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTRSRYDebtTokenBalance = vault.balanceOf(address(TRSRY)) + amount;

        // Call function
        vm.prank(USER);
        cooler.repayLoan(0, amount);

        // Token balances
        assertEq(vault.balanceOf(USER), expectedUserDebtTokenBalance, "USER debt token balance");
        assertEq(vault.balanceOf(address(clearinghouse)), 0, "clearinghouse debt token balance");
        assertEq(vault.balanceOf(address(cooler)), 0, "cooler debt token balance");
        assertEq(
            vault.balanceOf(address(CDEPO)),
            expectedCDEPODebtTokenBalance,
            "CDEPO debt token balance"
        );
        assertEq(
            vault.balanceOf(address(TRSRY)),
            expectedTRSRYDebtTokenBalance,
            "TRSRY debt token balance"
        );

        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral balance");
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral balance");
        assertEq(cdToken.balanceOf(address(cooler)), loan.collateral, "cooler collateral balance");

        // CDEPO debt
        // No principal repaid, so it remains the same
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), 1e18, "CDEPO debt");

        // Receivables
        assertEq(
            clearinghouse.interestReceivables(),
            loan.interestDue - amount,
            "interest receivables"
        );
        assertEq(clearinghouse.principalReceivables(), loan.principal, "principal receivables");
    }

    function test_repayPrincipal(
        uint256 amount_
    )
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToCooler(2e18)
    {
        // Determine the amount to repay
        ICooler.Loan memory loan = cooler.getLoan(0);
        uint256 totalDue = loan.principal + loan.interestDue;
        uint256 amount = bound(amount_, loan.interestDue + 1, totalDue);
        uint256 principalPaid = amount - loan.interestDue;
        uint256 expectedCollateralReturned = (loan.collateral * principalPaid) / loan.principal;

        // Ensure the user has enough debt tokens
        vm.prank(address(TRSRY));
        vault.transfer(USER, amount);

        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER) + expectedCollateralReturned;
        uint256 expectedUserDebtTokenBalance = vault.balanceOf(USER) - amount;
        uint256 expectedCDEPODebtTokenBalance = vault.balanceOf(address(CDEPO)) + principalPaid;
        uint256 expectedTRSRYDebtTokenBalance = vault.balanceOf(address(TRSRY)) + loan.interestDue;

        // Call function
        vm.prank(USER);
        cooler.repayLoan(0, amount);

        // Token balances
        assertEq(vault.balanceOf(USER), expectedUserDebtTokenBalance, "USER debt token balance");
        assertEq(vault.balanceOf(address(clearinghouse)), 0, "clearinghouse debt token balance");
        assertEq(vault.balanceOf(address(cooler)), 0, "cooler debt token balance");
        assertEq(
            vault.balanceOf(address(CDEPO)),
            expectedCDEPODebtTokenBalance,
            "CDEPO debt token balance"
        );
        assertEq(
            vault.balanceOf(address(TRSRY)),
            expectedTRSRYDebtTokenBalance,
            "TRSRY debt token balance"
        );

        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral balance");
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral balance");
        assertEq(
            cdToken.balanceOf(address(cooler)),
            loan.collateral - expectedCollateralReturned,
            "cooler collateral balance"
        );

        // CDEPO debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), totalDue - amount, "CDEPO debt");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interest receivables");
        assertEq(
            clearinghouse.principalReceivables(),
            loan.principal - principalPaid,
            "principal receivables"
        );
    }

    function test_repayPrincipal_givenDisabled(
        uint256 amount_
    )
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToCooler(2e18)
        givenDisabled
    {
        // Determine the amount to repay
        ICooler.Loan memory loan = cooler.getLoan(0);
        uint256 totalDue = loan.principal + loan.interestDue;
        uint256 amount = bound(amount_, loan.interestDue + 1, totalDue);
        uint256 principalPaid = amount - loan.interestDue;
        uint256 expectedCollateralReturned = (loan.collateral * principalPaid) / loan.principal;

        // Ensure the user has enough debt tokens
        vm.prank(address(TRSRY));
        vault.transfer(USER, amount);

        uint256 expectedUserCDEPOBalance = cdToken.balanceOf(USER) + expectedCollateralReturned;
        uint256 expectedUserDebtTokenBalance = vault.balanceOf(USER) - amount;
        uint256 expectedCDEPODebtTokenBalance = vault.balanceOf(address(CDEPO)) + principalPaid;
        uint256 expectedTRSRYDebtTokenBalance = vault.balanceOf(address(TRSRY)) + loan.interestDue;

        // Call function
        vm.prank(USER);
        cooler.repayLoan(0, amount);

        // Token balances
        assertEq(vault.balanceOf(USER), expectedUserDebtTokenBalance, "USER debt token balance");
        assertEq(vault.balanceOf(address(clearinghouse)), 0, "clearinghouse debt token balance");
        assertEq(vault.balanceOf(address(cooler)), 0, "cooler debt token balance");
        assertEq(
            vault.balanceOf(address(CDEPO)),
            expectedCDEPODebtTokenBalance,
            "CDEPO debt token balance"
        );
        assertEq(
            vault.balanceOf(address(TRSRY)),
            expectedTRSRYDebtTokenBalance,
            "TRSRY debt token balance"
        );

        assertEq(cdToken.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral balance");
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral balance");
        assertEq(
            cdToken.balanceOf(address(cooler)),
            loan.collateral - expectedCollateralReturned,
            "cooler collateral balance"
        );

        // CDEPO debt
        assertEq(CDEPO.debt(iAsset, address(clearinghouse)), totalDue - amount, "CDEPO debt");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), 0, "interest receivables");
        assertEq(
            clearinghouse.principalReceivables(),
            loan.principal - principalPaid,
            "principal receivables"
        );
    }
}

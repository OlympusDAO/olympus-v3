// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

import {Actions} from "src/Kernel.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {CDClearinghouse} from "src/policies/CDClearinghouse.sol";

contract ExtendLoanCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the cooler is not issued by the factory
    //  [X] it reverts
    // given the cooler loan was not issued by the Clearinghouse
    //  [X] it reverts
    // given the user has not approved spending of debt token
    //  [X] it reverts
    // given the user does not have enough debt token
    //  [X] it reverts
    // given the Clearinghouse is not enabled
    //  [X] it succeeds
    // [X] the interest is transferred from the user to the Clearinghouse
    // [X] the loan is extended
    // [X] the yield is swept to the TRSRY

    function test_notFromFactory_reverts() public givenUserHasCollateral(4e18) {
        CoolerFactory maliciousFactory = new CoolerFactory();
        vm.prank(USER);
        ICooler newCooler = ICooler(maliciousFactory.generateCooler(CDEPO, vault));

        // Set up a new Clearinghouse
        CDClearinghouse newClearinghouse = new CDClearinghouse(
            address(vault),
            address(maliciousFactory),
            address(kernel),
            0,
            121 days,
            1e18,
            1e18
        );
        vm.prank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));
        vm.prank(ADMIN);
        newClearinghouse.enable("");
        vm.label(address(newClearinghouse), "newClearinghouse");

        // Take a loan from the new Clearinghouse
        vm.startPrank(USER);
        CDEPO.approve(address(newClearinghouse), 2e18);
        newClearinghouse.lendToCooler(newCooler, 1e18);
        vm.stopPrank();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CoolerCallback.OnlyFromFactory.selector));

        // Call function
        vm.prank(USER);
        clearinghouse.extendLoan(newCooler, 0, 1);
    }

    function test_notFromClearinghouse_reverts()
        public
        givenUserHasCollateral(4e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(1e18)
    {
        // Set up a new Clearinghouse
        CDClearinghouse newClearinghouse = new CDClearinghouse(
            address(vault),
            address(coolerFactory),
            address(kernel),
            0,
            121 days,
            1e18,
            1e18
        );
        vm.prank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));
        vm.prank(ADMIN);
        newClearinghouse.enable("");
        vm.label(address(newClearinghouse), "newClearinghouse");

        // Take a loan from the new Clearinghouse
        vm.startPrank(USER);
        CDEPO.approve(address(newClearinghouse), 2e18);
        newClearinghouse.lendToCooler(cooler, 1e18);
        vm.stopPrank();

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICooler.OnlyApproved.selector));

        // Call function
        vm.prank(USER);
        clearinghouse.extendLoan(cooler, 0, 1);
    }

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
        clearinghouse.extendLoan(cooler, 0, 1);
    }

    function test_notEnoughDebt_reverts()
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
    {
        // Transfer debt to elsewhere
        vm.startPrank(USER);
        vault.transfer(OTHERS, vault.balanceOf(USER));
        vm.stopPrank();

        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        clearinghouse.extendLoan(cooler, 0, 1);
    }

    function test_givenDisabled()
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
        givenDisabled
    {
        ICooler.Loan memory loan = cooler.getLoan(0);

        uint256 expectedFees = loan.interestDue * 1;

        uint256 expectedUserCDEPOBalance = CDEPO.balanceOf(USER);
        uint256 expectedUserDebtTokenBalance = vault.balanceOf(USER) - expectedFees;
        uint256 expectedCDEPODebtTokenBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTRSRYDebtTokenBalance = vault.balanceOf(address(TRSRY)) + expectedFees;

        // Call function
        vm.prank(USER);
        clearinghouse.extendLoan(cooler, 0, 1);

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

        assertEq(CDEPO.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral balance");
        assertEq(CDEPO.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral balance");
        assertEq(CDEPO.balanceOf(address(cooler)), loan.collateral, "cooler collateral balance");

        // CDEPO debt
        // No principal repaid, so it remains the same
        assertEq(CDEPO.debt(address(clearinghouse)), 1e18, "CDEPO debt");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), loan.interestDue, "interest receivables");
        assertEq(clearinghouse.principalReceivables(), loan.principal, "principal receivables");

        // Cooler loan
        assertEq(cooler.getLoan(0).expiry, loan.expiry + 121 days, "cooler loan expiry");
    }

    function test_success(
        uint8 times_
    )
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
        givenUserHasDebt(1e18)
        givenUserHasApprovedDebtSpendingToClearinghouse(2e18)
    {
        uint8 times = uint8(bound(times_, 1, 10));

        ICooler.Loan memory loan = cooler.getLoan(0);

        uint256 expectedFees = loan.interestDue * times;

        uint256 expectedUserCDEPOBalance = CDEPO.balanceOf(USER);
        uint256 expectedUserDebtTokenBalance = vault.balanceOf(USER) - expectedFees;
        uint256 expectedCDEPODebtTokenBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTRSRYDebtTokenBalance = vault.balanceOf(address(TRSRY)) + expectedFees;

        // Call function
        vm.prank(USER);
        clearinghouse.extendLoan(cooler, 0, times);

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

        assertEq(CDEPO.balanceOf(USER), expectedUserCDEPOBalance, "USER collateral balance");
        assertEq(CDEPO.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral balance");
        assertEq(CDEPO.balanceOf(address(cooler)), loan.collateral, "cooler collateral balance");

        // CDEPO debt
        // No principal repaid, so it remains the same
        assertEq(CDEPO.debt(address(clearinghouse)), 1e18, "CDEPO debt");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), loan.interestDue, "interest receivables");
        assertEq(clearinghouse.principalReceivables(), loan.principal, "principal receivables");

        // Cooler loan
        assertEq(
            cooler.getLoan(0).expiry,
            loan.expiry + uint256(121 days) * uint256(times),
            "cooler loan expiry"
        );
    }
}

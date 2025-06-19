// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";
import {ICooler} from "src/external/cooler/interfaces/ICooler.sol";
import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {IGenericClearinghouse} from "src/policies/interfaces/IGenericClearinghouse.sol";

contract LendToCoolerCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the cooler is not issued by the factory
    //  [X] it reverts
    // given the cooler collateral is not CDEPO
    //  [X] it reverts
    // given the cooler debt is not the vault token
    //  [X] it reverts
    // given the Clearinghouse is not enabled
    //  [X] it reverts
    // given the user has not approved spending of collateral
    //  [X] it reverts
    // given the user does not have enough collateral
    //  [X] it reverts
    // [X] the user receives vault token
    // [X] the cooler receives collateral
    // [X] the debt is recorded on CDEPO
    /*
    function test_notFromFactory_reverts() public {
        CoolerFactory maliciousFactory = new CoolerFactory();
        vm.prank(USER);
        ICooler maliciousCooler = ICooler(maliciousFactory.generateCooler(cdToken, vault));

        // Expect revert
        vm.expectRevert(CoolerCallback.OnlyFromFactory.selector);

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(maliciousCooler, 1e18);
    }

    function test_collateralNotCDEPO_reverts() public {
        // Create a Cooler with a different collateral token
        ICooler cooler = ICooler(coolerFactory.generateCooler(asset, vault));

        // Expect revert
        vm.expectRevert(IGenericClearinghouse.BadEscrow.selector);

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);
    }

    function test_debtNotVault_reverts() public {
        // Create a Cooler with a different debt token
        ICooler cooler = ICooler(coolerFactory.generateCooler(cdToken, asset));

        // Expect revert
        vm.expectRevert(IGenericClearinghouse.BadEscrow.selector);

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);
    }

    function test_notEnabled_reverts() public givenDisabled {
        // Expect revert
        _expectNotEnabled();

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);
    }

    function test_spendingNotApproved_reverts() public givenUserHasCollateral(1e18) {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);
    }

    function test_notEnoughCollateral_reverts()
        public
        givenUserHasApprovedCollateralSpending(1e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);
    }

    function test_success()
        public
        givenUserHasApprovedCollateralSpending(4e18)
        givenUserHasCollateral(4e18)
    {
        uint256 expectedCollateralUsed = clearinghouse.getCollateralForLoan(1e18);
        uint256 expectedCollateralBalance = cdToken.balanceOf(USER) - expectedCollateralUsed;

        (uint256 principal, uint256 interest) = clearinghouse.getLoanForCollateral(
            expectedCollateralUsed
        );

        // Call function
        vm.prank(USER);
        clearinghouse.lendToCooler(cooler, 1e18);

        // Token balances
        assertEq(cdToken.balanceOf(USER), expectedCollateralBalance, "USER collateral");
        assertEq(cdToken.balanceOf(address(cooler)), expectedCollateralUsed, "cooler collateral");
        assertEq(cdToken.balanceOf(address(clearinghouse)), 0, "clearinghouse collateral");
        assertEq(vault.balanceOf(USER), 1e18, "USER vault");
        assertEq(vault.balanceOf(address(cooler)), 0, "cooler vault");
        assertEq(vault.balanceOf(address(clearinghouse)), 0, "clearinghouse vault");

        // Debt on CDEPO
        assertEq(CDEPO.getDebt(iVault, address(clearinghouse)), 1e18, "debt");

        // Receivables
        assertEq(clearinghouse.interestReceivables(), interest, "interest receivables");
        assertEq(clearinghouse.principalReceivables(), principal, "principal receivables");

        // Cooler Loan
        ICooler.Loan memory loan = cooler.getLoan(0);
        assertEq(loan.principal, 1e18, "loan principal");
        assertEq(loan.interestDue, interest, "loan interest due");
        assertEq(loan.collateral, expectedCollateralUsed, "loan collateral");
        assertEq(loan.lender, address(clearinghouse), "loan lender");
        assertEq(loan.expiry, block.timestamp + 121 days, "loan duration");
    }
    */
}

// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract RepayCDEPOTest is CDEPOTest {
    event Repaid(address borrower, uint256 amount);

    modifier givenAddressHasBorrowed(address borrower_, uint256 amount_) {
        vm.prank(address(godmode));
        CDEPO.borrow(amount_);
        _;
    }

    // when the caller is not permissioned
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the caller has not approved spending of the underlying asset
    //  [X] it reverts
    // when the amount is greater than the borrowed amount
    //  [X] it repays the borrowed amount
    //  [X] it transfers the borrowed amount from the caller to the contract
    //  [X] it returns the repaid amount
    // [X] it transfers the underlying asset to the contract
    // [X] it emits a Repaid event
    // [X] it updates the borrowed amount

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.repay(10e18);
    }

    function test_amountIsZero_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
        givenAddressHasBorrowed(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(address(godmode));
        CDEPO.repay(0);
    }

    function test_spendingNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
        givenAddressHasBorrowed(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(address(godmode));
        CDEPO.repay(10e18);
    }

    function test_amountIsGreaterThanBorrowed()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
        givenAddressHasBorrowed(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(address(godmode), address(CDEPO), 10e18)
    {
        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO)) +
            vault.previewDeposit(10e18);

        // Call function
        vm.prank(address(godmode));
        uint256 repaidAmount = CDEPO.repay(10e18 + 1);

        // Assert balances
        assertEq(reserveToken.balanceOf(address(godmode)), 0, "godmode: reserve token balance");
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), 0, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(CDEPO.borrowed(address(godmode)), 0, "borrowed");

        // Assert repaid amount
        assertEq(repaidAmount, 10e18, "repaid amount");
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
        givenAddressHasBorrowed(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(address(godmode), address(CDEPO), 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO)) +
            vault.convertToShares(amount);

        // Call function
        vm.prank(address(godmode));
        uint256 repaidAmount = CDEPO.repay(amount);

        // Assert balances
        assertEq(
            reserveToken.balanceOf(address(godmode)),
            10e18 - amount,
            "godmode: reserve token balance"
        );
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), 0, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(CDEPO.borrowed(address(godmode)), 10e18 - amount, "borrowed");

        // Assert repaid amount
        assertEq(repaidAmount, amount, "repaid amount");
    }
}

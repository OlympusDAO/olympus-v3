// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract BorrowCDEPOTest is CDEPOTest {
    event Borrowed(address borrower, uint256 amount);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than the balance of the contract
    //  [X] it reverts
    // [X] it transfers the underlying asset to the caller
    // [X] it emits a Borrowed event
    // [X] it updates the borrowed amount

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.borrow(10e18);
    }

    function test_amountIsZero_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(address(godmode));
        CDEPO.borrow(0);
    }

    function test_amountIsGreaterThanBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InsufficientBalance.selector));

        // Call function
        vm.prank(address(godmode));
        CDEPO.borrow(100e18 + 1);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO)) -
            vault.previewWithdraw(amount);

        // Expect event
        vm.expectEmit();
        emit Borrowed(address(godmode), amount);

        // Call function
        vm.prank(address(godmode));
        CDEPO.borrow(amount);

        // Assert balances
        assertEq(
            reserveToken.balanceOf(address(godmode)),
            amount,
            "godmode: reserve token balance"
        );
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), 0, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(CDEPO.borrowed(address(godmode)), amount, "borrowed");
    }
}

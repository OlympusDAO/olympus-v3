// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract ReduceDebtCDEPOTest is CDEPOTest {
    event DebtReduced(address indexed inputToken, address indexed borrower, uint256 amount);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the input token is not supported
    //  [X] it reverts
    // when the input token is a convertible deposit token
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than the borrowed amount
    //  [X] it emits a DebtReduced event
    //  [X] it reduces the debt by the borrowed amount
    // [X] it emits a DebtReduced event
    // [X] it updates the borrowed amount

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.reduceDebt(iReserveToken, 10e18);
    }

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(godmode);
        CDEPO.reduceDebt(iReserveTokenTwo, 10e18);
    }

    function test_convertibleDepositToken_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(address(godmode));
        CDEPO.reduceDebt(IERC20(address(cdToken)), 10e18);
    }

    function test_amountIsZero_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        vm.prank(address(godmode));
        CDEPO.reduceDebt(iReserveToken, 0);
    }

    function test_amountIsGreaterThanBorrowedAmount()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenAddressHasBorrowed(10e18)
    {
        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));

        // Expect event
        vm.expectEmit();
        emit DebtReduced(address(iReserveToken), address(godmode), 10e18);

        // Call function
        vm.prank(address(godmode));
        uint256 actualAmount = CDEPO.reduceDebt(iReserveToken, 10e18 + 1);

        // Assert balances
        assertEq(reserveToken.balanceOf(address(godmode)), 0, "godmode: reserve token balance");
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), 10e18, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(actualAmount, 10e18, "borrowed amount");
        assertEq(CDEPO.debt(iReserveToken, address(godmode)), 0, "debt");
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenAddressHasBorrowed(10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));

        // Expect event
        vm.expectEmit();
        emit DebtReduced(address(iReserveToken), address(godmode), amount);

        // Call function
        vm.prank(address(godmode));
        uint256 actualAmount = CDEPO.reduceDebt(iReserveToken, amount);

        // Assert balances
        assertEq(reserveToken.balanceOf(address(godmode)), 0, "godmode: reserve token balance");
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), 10e18, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(actualAmount, amount, "borrowed amount");
        assertEq(CDEPO.debt(iReserveToken, address(godmode)), 10e18 - amount, "debt");
    }
}

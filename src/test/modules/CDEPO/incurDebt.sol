// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

contract IncurDebtCDEPOTest is CDEPOTest {
    event DebtIncurred(address indexed inputToken, address indexed borrower, uint256 amount);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the deposit token is not supported
    //  [X] it reverts
    // when the deposit token is a convertible deposit token
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than the balance of the contract
    //  [X] it reverts
    // [X] it transfers the vault asset to the caller
    // [X] it emits a DebtIncurred event
    // [X] it updates the borrowed amount

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.incurDebt(iReserveTokenVault, 10e18);
    }

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(godmode);
        CDEPO.incurDebt(iReserveTokenTwoVault, 10e18);
    }

    function test_convertibleDepositToken_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(address(godmode));
        CDEPO.incurDebt(IERC4626(address(cdToken)), 10e18);
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
        CDEPO.incurDebt(iReserveTokenVault, 0);
    }

    function test_amountIsGreaterThanBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InsufficientBalance.selector)
        );

        // Call function
        vm.prank(address(godmode));
        CDEPO.incurDebt(iReserveTokenVault, 100e18 + 1);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO)) - amount;

        // Expect event
        vm.expectEmit();
        emit DebtIncurred(address(iReserveTokenVault), address(godmode), amount);

        // Call function
        vm.prank(address(godmode));
        CDEPO.incurDebt(iReserveTokenVault, amount);

        // Assert balances
        assertEq(reserveToken.balanceOf(address(godmode)), 0, "godmode: reserve token balance");
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO: reserve token balance");
        assertEq(vault.balanceOf(address(godmode)), amount, "godmode: vault balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "CDEPO: vault balance");

        // Assert borrowed amount
        assertEq(CDEPO.getDebt(iReserveTokenVault, address(godmode)), amount, "debt");
    }
}

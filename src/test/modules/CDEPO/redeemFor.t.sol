// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract RedeemForCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the shares for the amount is zero
    //  [X] it reverts
    // when the account address has not approved CDEPO to spend the convertible deposit tokens
    //  when the account address is the same as the sender
    //   [X] it does not require the approval
    //  [X] it reverts
    // when the account address has an insufficient balance of convertible deposit tokens
    //  [X] it reverts
    // when the account address has a sufficient balance of convertible deposit tokens
    //  [X] it burns the corresponding amount of convertible deposit tokens from the account address
    //  [X] it withdraws the underlying asset from the vault
    //  [X] it transfers the underlying asset to the caller and does not apply the reclaim rate

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.redeemFor(iReserveToken, recipient, 0);
    }

    function test_spendingNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "allowance")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.redeemFor(iReserveToken, recipient, 10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 5e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 5e18)
        givenAddressHasCDToken(recipient, 5e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(godmode);
        CDEPO.redeemFor(iReserveToken, recipient, 10e18);
    }

    function test_callerIsNotPermissioned_reverts() public {
        // Expect revert
        _expectRevertPolicyNotPermitted(recipient);

        // Call function
        vm.prank(recipient);
        CDEPO.redeemFor(iReserveToken, recipient, 10e18);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        uint256 amount = bound(amount_, 1, 10e18);

        uint256 vaultBalanceBefore = vault.balanceOf(address(CDEPO));
        uint256 expectedVaultSharesWithdrawn = vault.previewWithdraw(amount);

        // Call function
        vm.prank(godmode);
        CDEPO.redeemFor(iReserveToken, recipient, amount);

        // Assert CD token balance
        assertEq(
            _getCDToken().balanceOf(recipient),
            10e18 - amount,
            "_getCDToken().balanceOf(recipient)"
        );
        assertEq(_getCDToken().balanceOf(godmode), 0, "_getCDToken().balanceOf(godmode)");
        assertEq(_getCDToken().totalSupply(), 10e18 - amount, "_getCDToken().totalSupply()");

        // Assert reserve token balance
        // No reclaim rate is applied
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");
        assertEq(reserveToken.balanceOf(godmode), amount, "reserveToken.balanceOf(godmode)");
        assertEq(
            reserveToken.balanceOf(address(CDEPO)),
            0,
            "reserveToken.balanceOf(address(CDEPO))"
        );
        assertEq(
            reserveToken.balanceOf(address(vault)),
            reserveToken.totalSupply() - amount,
            "reserveToken.balanceOf(address(vault))"
        );

        // Assert vault balance
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
        assertEq(vault.balanceOf(godmode), 0, "vault.balanceOf(godmode)");
        assertEq(
            vault.balanceOf(address(CDEPO)),
            vaultBalanceBefore - expectedVaultSharesWithdrawn,
            "vault.balanceOf(address(CDEPO))"
        );

        // Assert total shares tracked
        _assertTotalShares(amount);
    }

    function test_success_sameAddress()
        public
        givenAddressHasReserveToken(godmode, 10e18)
        givenReserveTokenSpendingIsApproved(godmode, address(CDEPO), 10e18)
        givenAddressHasCDToken(godmode, 10e18)
    {
        uint256 amount = 5e18;

        uint256 vaultBalanceBefore = vault.balanceOf(address(CDEPO));
        uint256 expectedVaultSharesWithdrawn = vault.previewWithdraw(amount);

        // Call function
        vm.prank(godmode);
        CDEPO.redeemFor(iReserveToken, godmode, amount);

        // Assert CD token balance
        assertEq(_getCDToken().balanceOf(recipient), 0, "_getCDToken().balanceOf(recipient)");
        assertEq(
            _getCDToken().balanceOf(godmode),
            10e18 - amount,
            "_getCDToken().balanceOf(godmode)"
        );
        assertEq(_getCDToken().totalSupply(), 10e18 - amount, "_getCDToken().totalSupply()");

        // Assert reserve token balance
        // No reclaim rate is applied
        assertEq(reserveToken.balanceOf(recipient), 0, "reserveToken.balanceOf(recipient)");
        assertEq(reserveToken.balanceOf(godmode), amount, "reserveToken.balanceOf(godmode)");
        assertEq(
            reserveToken.balanceOf(address(CDEPO)),
            0,
            "reserveToken.balanceOf(address(CDEPO))"
        );
        assertEq(
            reserveToken.balanceOf(address(vault)),
            reserveToken.totalSupply() - amount,
            "reserveToken.balanceOf(address(vault))"
        );

        // Assert vault balance
        assertEq(vault.balanceOf(recipient), 0, "vault.balanceOf(recipient)");
        assertEq(vault.balanceOf(godmode), 0, "vault.balanceOf(godmode)");
        assertEq(
            vault.balanceOf(address(CDEPO)),
            vaultBalanceBefore - expectedVaultSharesWithdrawn,
            "vault.balanceOf(address(CDEPO))"
        );

        // Assert total shares tracked
        _assertTotalShares(amount);
    }
}

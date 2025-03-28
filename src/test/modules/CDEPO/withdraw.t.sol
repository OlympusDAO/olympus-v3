// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {stdError} from "forge-std/StdError.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract WithdrawCDEPOv1Test is CDEPOTest {
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    // when the caller is not permissioned
    //  [X] it reverts
    // when the token is not supported
    //  [X] it reverts
    // when the amount is greater than the balance
    //  [X] it reverts
    // [X] it transfer the token to the caller
    // [X] it updates the total shares
    // [X] it emits a `TokenWithdrawn` event

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.withdraw(cdToken, 10e18);
    }

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        vm.prank(godmode);
        CDEPO.withdraw(IConvertibleDepositERC20(address(iReserveTokenTwoVault)), 10e18);
    }

    function test_amountIsGreaterThanDepositedAmount()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(address(godmode));
        CDEPO.withdraw(cdToken, INITIAL_VAULT_BALANCE + 10e18 + 1);
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
        uint256 amountInShares = cdToken.vault().previewWithdraw(amount);
        uint256 vaultBalanceBefore = cdToken.vault().balanceOf(address(CDEPO));

        // Expect event
        vm.expectEmit();
        emit TokenWithdrawn(address(iReserveToken), address(godmode), amount);

        // Call function
        vm.prank(address(godmode));
        CDEPO.withdraw(cdToken, amount);

        // Caller receives the amount of underlying tokens
        assertEq(reserveToken.balanceOf(godmode), amount, "godmode: reserve token balance");

        // CDEPO vault balance decreases by the amount in shares
        assertEq(
            cdToken.vault().balanceOf(address(CDEPO)),
            vaultBalanceBefore - amountInShares,
            "CDEPO: vault balance"
        );

        // Total shares decreases by the amount in shares
        assertEq(
            CDEPO.getVaultShares(iReserveTokenVault),
            vaultBalanceBefore - amountInShares,
            "CDEPO: total shares"
        );
    }
}

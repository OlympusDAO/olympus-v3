// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {stdError} from "forge-std/StdError.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

contract BurnCDEPOTest is CDEPOTest {
    // when the caller has an insufficient balance
    //  [X] it reverts
    // when the last CD token is burned
    //  [X] it burns the correct amount
    //  [X] it updates the total shares to 0
    // [X] it burns the correct amount
    // [X] it updates the total shares

    function test_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        CDEPO.burn(10e18);
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

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTotalShares = CDEPO.totalShares() - vault.previewWithdraw(amount);
        uint256 expectedTotalSupply = CDEPO.totalSupply() - amount;

        // Call function
        vm.prank(recipient);
        CDEPO.burn(amount);

        // Assert balances
        assertEq(CDEPO.balanceOf(recipient), 10e18 - amount, "CDEPO: recipient balance");
        assertEq(vault.balanceOf(recipient), 0, "vault: recipient balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "vault: CDEPO balance");

        // Assert total shares
        assertEq(CDEPO.totalShares(), expectedTotalShares, "total shares");
        assertEq(CDEPO.totalSupply(), expectedTotalSupply, "total supply");
    }

    function test_lastToken()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipient, 10e18)
    {
        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTotalShares = CDEPO.totalShares() - vault.previewWithdraw(10e18);

        // Call function
        vm.prank(recipient);
        CDEPO.burn(10e18);

        // Assert balances
        assertEq(CDEPO.balanceOf(recipient), 0, "CDEPO: recipient balance");
        assertEq(vault.balanceOf(recipient), 0, "vault: recipient balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "vault: CDEPO balance");

        // Assert total shares
        assertEq(CDEPO.totalShares(), expectedTotalShares, "total shares");
        assertEq(CDEPO.totalSupply(), 0, "total supply");

        // Sweeping yield should bring total shares to 0
        vm.prank(address(godmode));
        CDEPO.sweepYield(address(this));

        assertEq(CDEPO.totalShares(), 0, "total shares after sweep");
    }
}

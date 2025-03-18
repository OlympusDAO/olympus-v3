// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {stdError} from "forge-std/StdError.sol";
import {CDEPOTest} from "./CDEPOTest.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract BurnCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when the caller has an insufficient balance
    //  [X] it reverts
    // when the caller has not approved the CDEPO to spend the amount
    //  [X] it reverts
    // when the last CD token is burned
    //  [X] it burns the correct amount
    //  [X] it updates the total shares to 0
    // [X] it burns the correct amount
    // [X] it updates the total shares

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.burn(iReserveTokenTwo, 10e18);
    }

    function test_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        CDEPO.burn(iReserveToken, 10e18);
    }

    function test_spendingNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.burn(iReserveToken, 10e18);
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
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTotalShares = _getTotalShares() - vault.previewWithdraw(amount);
        uint256 expectedTotalSupply = _getCDToken().totalSupply() - amount;

        // Call function
        vm.prank(recipient);
        CDEPO.burn(iReserveToken, amount);

        // Assert balances
        assertEq(_getCDToken().balanceOf(recipient), 10e18 - amount, "CDEPO: recipient balance");
        assertEq(vault.balanceOf(recipient), 0, "vault: recipient balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "vault: CDEPO balance");

        // Assert total shares
        assertEq(_getTotalShares(), expectedTotalShares, "total shares");
        assertEq(_getCDToken().totalSupply(), expectedTotalSupply, "total supply");
    }

    function test_lastToken()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipient, 10e18)
    {
        uint256 expectedVaultBalance = vault.balanceOf(address(CDEPO));
        uint256 expectedTotalShares = _getTotalShares() - vault.previewWithdraw(10e18);

        // Call function
        vm.prank(recipient);
        CDEPO.burn(iReserveToken, 10e18);

        // Assert balances
        assertEq(_getCDToken().balanceOf(recipient), 0, "CDEPO: recipient balance");
        assertEq(vault.balanceOf(recipient), 0, "vault: recipient balance");
        assertEq(vault.balanceOf(address(CDEPO)), expectedVaultBalance, "vault: CDEPO balance");

        // Assert total shares
        assertEq(_getTotalShares(), expectedTotalShares, "total shares");
        assertEq(_getCDToken().totalSupply(), 0, "total supply");

        // Sweeping yield should bring total shares to 0
        vm.prank(address(godmode));
        CDEPO.sweepYield(iReserveToken, address(this));

        assertEq(_getTotalShares(), 0, "total shares after sweep");
    }
}

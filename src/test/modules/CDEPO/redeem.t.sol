// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {Module} from "src/Kernel.sol";

import {console2} from "forge-std/console2.sol";

contract RedeemCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the shares for the amount is zero
    //  [X] it reverts
    // when the amount is greater than the caller's balance
    //  [X] it reverts
    // when the caller is not permissioned
    //  [X] it reverts
    // when the caller is permissioned
    //  [X] it burns the corresponding amount of convertible deposit tokens
    //  [X] it withdraws the underlying asset from the vault
    //  [X] it transfers the underlying asset to the caller and does not apply the reclaim rate

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(godmode);
        CDEPO.redeem(0);
    }

    // Cannot test this, as the vault will round up the number of shares withdrawn
    // A different ERC4626 vault implementation may trigger the condition though
    // function test_sharesForAmountIsZero_reverts()
    //     public
    //     givenAddressHasReserveToken(godmode, 10e18)
    //     givenReserveTokenSpendingIsApproved(godmode, address(CDEPO), 10e18)
    //     givenAddressHasCDEPO(godmode, 10e18)
    // {
    //     // Deposit more reserve tokens into the vault to that the shares returned is 0
    //     reserveToken.mint(address(vault), 100e18);

    //     // This amount would result in 0 shares being withdrawn, and should revert
    //     uint256 amount = 1;

    //     // Expect revert
    //     vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "shares"));

    //     // Call function
    //     vm.prank(godmode);
    //     CDEPO.redeem(amount);
    // }

    function test_amountIsGreaterThanBalance_reverts()
        public
        givenAddressHasReserveToken(godmode, 10e18)
        givenReserveTokenSpendingIsApproved(godmode, address(CDEPO), 10e18)
        givenAddressHasCDEPO(godmode, 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(godmode);
        CDEPO.redeem(10e18 + 1);
    }

    function test_callerIsNotPermissioned_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(Module.Module_PolicyNotPermitted.selector, recipient)
        );

        // Call function
        vm.prank(recipient);
        CDEPO.redeem(10e18);
    }

    function test_success(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(godmode, 10e18)
        givenReserveTokenSpendingIsApproved(godmode, address(CDEPO), 10e18)
        givenAddressHasCDEPO(godmode, 10e18)
    {
        uint256 amount = bound(amount_, 1, 10e18);

        // Call function
        vm.prank(godmode);
        CDEPO.redeem(amount);

        // Assert CD token balance
        assertEq(CDEPO.balanceOf(godmode), 10e18 - amount, "CD token balance");
        assertEq(CDEPO.totalSupply(), 10e18 - amount, "CD token total supply");

        // Assert reserve token balance
        // No reclaim rate is applied
        assertEq(reserveToken.balanceOf(godmode), amount, "godmode reserve token balance");
        assertEq(reserveToken.balanceOf(address(CDEPO)), 0, "CDEPO reserve token balance");
        assertEq(
            reserveToken.balanceOf(address(vault)),
            reserveToken.totalSupply() - amount,
            "vault reserve token balance"
        );

        // Assert total shares tracked
        _assertTotalShares(amount);
    }
}

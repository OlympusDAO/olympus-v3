// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

import {console2} from "forge-std/console2.sol";

contract ReclaimForCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the discounted amount is zero
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
    //  [X] it transfers the underlying asset to the account address after applying the reclaim rate
    //  [X] it marks the forfeited amount of the underlying asset as yield
    //  [X] it updates the total deposits

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, 0);
    }

    function test_discountedAmountIsZero_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDEPO(10e18)
    {
        // This amount would result in 0 shares being withdrawn, and should revert
        uint256 amount = 1;

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "shares"));

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, amount);
    }

    function test_spendingIsNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipientTwo, 10e18)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "allowance"));

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, 10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 5e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 5e18)
        givenAddressHasCDEPO(recipientTwo, 5e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, 10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipientTwo, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, 10e18);

        // Assert balances
        _assertReserveTokenBalance(0, expectedReserveTokenAmount);
        _assertCDEPOBalance(0, 0);
        _assertVaultBalance(0, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }

    function test_success_sameAddress()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipientTwo, 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipientTwo);
        CDEPO.reclaimFor(recipientTwo, 10e18);

        // Assert balances
        _assertReserveTokenBalance(0, expectedReserveTokenAmount);
        _assertCDEPOBalance(0, 0);
        _assertVaultBalance(0, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }

    function test_success_fuzz(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDEPO(recipientTwo, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedReserveTokenAmount = FullMath.mulDiv(amount, reclaimRate, 100e2);
        uint256 forfeitedAmount = amount - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(recipientTwo, amount);

        // Assert balances
        _assertReserveTokenBalance(0, expectedReserveTokenAmount);
        _assertCDEPOBalance(0, 10e18 - amount);
        _assertVaultBalance(0, 10e18 - amount, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }
}
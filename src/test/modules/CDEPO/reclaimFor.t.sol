// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

contract ReclaimForCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
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
    //  [X] it transfers the underlying asset to the caller after applying the reclaim rate
    //  [X] it marks the forfeited amount of the underlying asset as yield
    //  [X] it updates the total deposits

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.reclaimFor(iReserveTokenTwo, recipient, 10e18);
    }

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, 0);
    }

    function test_discountedAmountIsZero_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDToken(10e18)
    {
        // This amount would result in 0 shares being withdrawn, and should revert
        uint256 amount = 1;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepository.CDEPO_InvalidArgs.selector,
                "reclaimed amount"
            )
        );

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, amount);
    }

    function test_spendingIsNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipientTwo, 10e18)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "allowance")
        );

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, 10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 5e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 5e18)
        givenAddressHasCDToken(recipientTwo, 5e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, 10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipientTwo, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, 10e18);

        // Assert balances
        _assertReserveTokenBalance(expectedReserveTokenAmount, 0);
        _assertCDEPOBalance(0, 0);
        _assertVaultBalance(0, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }

    function test_success_sameAddress()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
        givenAddressHasCDToken(recipientTwo, 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipientTwo);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, 10e18);

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
        givenAddressHasCDToken(recipientTwo, 10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedReserveTokenAmount = FullMath.mulDiv(amount, reclaimRate, 100e2);
        uint256 forfeitedAmount = amount - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaimFor(iReserveToken, recipientTwo, amount);

        // Assert balances
        _assertReserveTokenBalance(expectedReserveTokenAmount, 0);
        _assertCDEPOBalance(0, 10e18 - amount);
        _assertVaultBalance(0, 10e18 - amount, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }
}

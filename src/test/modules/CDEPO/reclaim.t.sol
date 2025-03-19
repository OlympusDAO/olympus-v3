// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract ReclaimCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the discounted amount is zero
    //  [X] it reverts
    // when the shares for the discounted amount is zero
    //  [X] it reverts
    // when the amount is greater than the caller's balance
    //  [X] it reverts
    // when the caller has not approved spending of the convertible deposit tokens
    //  [X] it reverts
    // when the amount is greater than zero
    //  [X] it burns the corresponding amount of convertible deposit tokens
    //  [X] it withdraws the underlying asset from the vault
    //  [X] it transfers the underlying asset to the caller after applying the burn rate
    //  [X] it updates the total deposits
    //  [X] it marks the forfeited amount of the underlying asset as yield

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.reclaim(IConvertibleDepositERC20(address(iReserveToken)), 10e18);
    }

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(cdToken, 0);
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
        CDEPO.reclaim(cdToken, amount);
    }

    function test_insufficientAllowance_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 5e18)
        givenRecipientHasCDToken(5e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(cdToken, 10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 5e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 5e18)
        givenRecipientHasCDToken(5e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 5e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(cdToken, 10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDToken(10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(cdToken, 10e18);

        // Assert balances
        _assertReserveTokenBalance(expectedReserveTokenAmount, 0);
        _assertCDEPOBalance(0, 0);
        _assertVaultBalance(0, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }

    function test_success_fuzz(
        uint256 amount_
    )
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDToken(10e18)
        givenConvertibleDepositTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        uint256 amount = bound(amount_, 2, 10e18);

        uint256 expectedReserveTokenAmount = FullMath.mulDiv(amount, reclaimRate, 100e2);
        uint256 forfeitedAmount = amount - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(cdToken, amount);

        // Assert balances
        _assertReserveTokenBalance(expectedReserveTokenAmount, 0);
        _assertCDEPOBalance(10e18 - amount, 0);
        _assertVaultBalance(10e18 - amount, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }
}

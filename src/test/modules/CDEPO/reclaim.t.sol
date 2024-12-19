// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test, stdError} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {console2} from "forge-std/console2.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract ReclaimCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the amount is greater than the caller's balance
    //  [X] it reverts
    // when the amount is greater than zero
    //  [ X] it burns the corresponding amount of convertible deposit tokens
    //  [X] it withdraws the underlying asset from the vault
    //  [X] it transfers the underlying asset to the caller after applying the burn rate
    //  [X] it updates the total deposits
    //  [X] it marks the forfeited amount of the underlying asset as yield

    function test_amountIsZero_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(0);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 5e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 5e18)
        givenRecipientHasCDEPO(5e18)
        givenCDEPOSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert(stdError.arithmeticError);

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(recipient, address(CDEPO), 10e18)
        givenRecipientHasCDEPO(10e18)
        givenCDEPOSpendingIsApproved(recipient, address(CDEPO), 10e18)
    {
        uint256 expectedReserveTokenAmount = FullMath.mulDiv(10e18, reclaimRate, 100e2);
        assertEq(expectedReserveTokenAmount, 99e17, "expectedReserveTokenAmount");
        uint256 forfeitedAmount = 10e18 - expectedReserveTokenAmount;

        // Call function
        vm.prank(recipient);
        CDEPO.reclaim(10e18);

        // Assert balances
        _assertReserveTokenBalance(expectedReserveTokenAmount, 0);
        _assertCDEPOBalance(0, 0);
        _assertVaultBalance(0, 0, forfeitedAmount);

        // Assert deposits
        _assertTotalShares(expectedReserveTokenAmount);
    }
}

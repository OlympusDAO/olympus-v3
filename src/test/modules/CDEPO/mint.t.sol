// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {CDEPOTest} from "./CDEPOTest.sol";

import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";

contract MintCDEPOTest is CDEPOTest {
    // when the amount is zero
    //  [X] it reverts
    // when the caller has not approved CDEPO to spend reserve tokens
    //  [X] it reverts
    // when the caller has approved CDEPO to spend reserve tokens
    //  when the caller has an insufficient balance of reserve tokens
    //   [X] it reverts
    //  when the caller has a sufficient balance of reserve tokens
    //   [X] it transfers the reserve tokens to CDEPO
    //   [X] it mints an equal amount of convertible deposit tokens to the caller
    //   [X] it deposits the reserve tokens into the vault

    function test_zeroAmount_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(CDEPOv1.CDEPO_InvalidArgs.selector, "amount"));

        // Call function
        _mint(0);
    }

    function test_spendingNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipient, 10e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _mint(10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipient, 5e18)
        givenReserveTokenSpendingIsApproved(address(recipient), address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _mint(10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipient, 10e18)
        givenReserveTokenSpendingIsApproved(address(recipient), address(CDEPO), 10e18)
    {
        // Call function
        _mint(10e18);

        // Assert balances
        _assertReserveTokenBalance(0, 0);
        _assertCDEPOBalance(10e18, 0);
        _assertVaultBalance(10e18, 0, 0);
    }
}
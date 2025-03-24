// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract MintForCDEPOTest is CDEPOTest {
    // when the input token is not supported
    //  [X] it reverts
    // when the recipient is the zero address
    //  [X] it reverts
    // when the amount is zero
    //  [X] it reverts
    // when the account address has not approved CDEPO to spend reserve tokens
    //  when the account address is the same as the sender
    //   [X] it reverts
    //  [X] it reverts
    // when the account address has an insufficient balance of reserve tokens
    //  [X] it reverts
    // when the account address has a sufficient balance of reserve tokens
    //  [X] it transfers the reserve tokens to CDEPO
    //  [X] it mints an equal amount of convertible deposit tokens to the `account_` address
    //  [X] it deposits the reserve tokens into the vault

    function test_notSupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_UnsupportedToken.selector)
        );

        // Call function
        CDEPO.mintFor(IConvertibleDepositERC20(address(iReserveToken)), recipient, 10e18);
    }

    function test_zeroAmount_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "amount")
        );

        // Call function
        _mintFor(recipient, recipientTwo, 0);
    }

    function test_spendingNotApproved_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _mintFor(recipient, recipientTwo, 10e18);
    }

    function test_spendingNotApproved_sameAddress_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
    {
        // Expect revert
        // This is because the underlying asset needs to be transferred to the CDEPO contract, regardless of the caller
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _mintFor(recipientTwo, recipientTwo, 10e18);
    }

    function test_insufficientBalance_reverts()
        public
        givenAddressHasReserveToken(recipientTwo, 5e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        _mintFor(recipient, recipientTwo, 10e18);
    }

    function test_success()
        public
        givenAddressHasReserveToken(recipientTwo, 10e18)
        givenReserveTokenSpendingIsApproved(recipientTwo, address(CDEPO), 10e18)
    {
        // Call function
        _mintFor(recipient, recipientTwo, 10e18);

        // Assert balances
        _assertReserveTokenBalance(0, 0);
        _assertCDEPOBalance(0, 10e18);
        _assertVaultBalance(0, 10e18, 0);
    }
}

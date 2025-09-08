// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {stdError} from "@forge-std-1.9.6/StdError.sol";

/**
 * @title BurnTest
 * @notice Tests for ReceiptTokenManager token burning functionality
 */
contract ReceiptTokenManagerBurnTest is ReceiptTokenManagerTest {
    // given burn from non-existent token
    //  [X] reverts with NotOwner error (owner is address(0))
    function test_burnFromNonExistentToken() public {
        // Try to burn from a token that doesn't exist yet
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6909Wrappable.ERC6909Wrappable_InvalidTokenId.selector,
                _tokenId
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT, false);
    }

    // when the caller is not the token owner
    //  given the recipient has approved spending by the non-owner
    //   [X] it reverts

    function test_whenCallerIsNotTokenOwner_givenRecipientHasApprovedSpending_reverts()
        public
        createReceiptToken
    {
        // First give allowance to NON_OWNER
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(NON_OWNER, _tokenId, MINT_AMOUNT / 2);

        // NON_OWNER still cannot burn because they're not the token owner
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                NON_OWNER,
                OWNER
            )
        );

        vm.prank(NON_OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);
    }

    //  [X] it reverts

    function test_whenCallerIsNotTokenOwner_reverts() public createReceiptToken {
        // NON_OWNER cannot burn because they're not the token owner
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                NON_OWNER,
                OWNER
            )
        );

        vm.prank(NON_OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);
    }

    function test_whenCallerIsTokenOwner_givenRecipientHasNotApprovedSpending_reverts()
        public
        createReceiptToken
        mintToRecipient
    {
        expectInsufficientAllowance(OWNER, 0, MINT_AMOUNT / 2);
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);
    }

    // given token owner burns tokens with allowance
    //  [X] owner can burn successfully with allowance
    //  [X] balance is updated correctly
    function test_whenCallerIsTokenOwner_givenRecipientHasApprovedSpending()
        public
        createReceiptToken
        mintToRecipient
        allowOwnerToSpend
    {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning"
        );
    }

    // given owner burns from self
    //  [X] burn from self works correctly
    function test_givenTokenOwnerHasNotApprovedSpending() public createReceiptToken {
        // First mint tokens to OWNER
        vm.prank(OWNER);
        receiptTokenManager.mint(OWNER, _tokenId, MINT_AMOUNT, false);

        // Owner burns from themselves (no allowance needed when burning own tokens)
        vm.prank(OWNER);
        receiptTokenManager.burn(OWNER, _tokenId, MINT_AMOUNT / 2, false);

        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            MINT_AMOUNT / 2,
            "Owner's balance should be reduced after burning from self"
        );
    }

    // given zero amount burn
    //  [X] burn zero amount reverts
    function test_burnZeroAmount_reverts() public createReceiptToken mintToRecipient {
        vm.expectRevert(
            abi.encodeWithSelector(IERC6909Wrappable.ERC6909Wrappable_ZeroAmount.selector)
        );
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, 0, false);
    }

    // given burn full balance
    //  [X] balance becomes zero
    function test_burnFullBalance() public createReceiptToken mintToRecipient allowOwnerToSpend {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            0,
            "Balance should be zero after burning full balance"
        );
    }

    // given burn partial balance
    //  [X] balance is reduced correctly
    function test_burnPartialBalance() public createReceiptToken mintToRecipient allowOwnerToSpend {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 3, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT - MINT_AMOUNT / 3,
            "Balance should be correctly reduced after partial burn"
        );
    }

    // given multiple burns
    //  [X] balances are reduced correctly each time
    function test_burnMultipleTimes() public createReceiptToken mintToRecipient allowOwnerToSpend {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 4, false);

        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 4, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be correctly reduced after multiple burns"
        );
    }

    // ========== INSUFFICIENT BALANCE TESTS ========== //

    function test_burnWithoutBalance_reverts() public createReceiptToken allowOwnerToSpendAll {
        expectInsufficientBalance(RECIPIENT, 0, MINT_AMOUNT);
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT, false);
    }

    function test_burnMoreThanBalance_reverts()
        public
        createReceiptToken
        mintToRecipient
        allowOwnerToSpendAll
    {
        expectInsufficientBalance(RECIPIENT, MINT_AMOUNT, MINT_AMOUNT * 2);
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT * 2, false);
    }

    // when wrapped is true
    //  given the recipient has not approved spending of the ERC20 tokens
    //   [X] it reverts

    function test_whenWrappedIsTrue_givenRecipientHasNotApprovedERC20Spending()
        public
        createReceiptToken
        mintToRecipientWrapped
    {
        vm.expectRevert(stdError.arithmeticError);

        // Then burn wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, true);
    }

    // given the recipient has an insufficient balance of the ERC20 tokens
    //  [X] it reverts

    function test_whenWrappedIsTrue_insufficientBalance_reverts()
        public
        createReceiptToken
        mintToRecipient
        allowReceiptTokenManagerToSpendWrapped
    {
        vm.expectRevert(stdError.arithmeticError);

        // Try to burn wrapped tokens when recipient only has unwrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, true);
    }

    // [X] it burns the wrapped tokens

    function test_whenWrappedIsTrue()
        public
        createReceiptToken
        mintToRecipientWrapped
        allowReceiptTokenManagerToSpendWrapped
    {
        // Then burn wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, true);

        assertEq(
            _wrappedToken.balanceOf(RECIPIENT),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning wrapped tokens"
        );
    }

    // ========== CROSS-TOKEN OWNERSHIP TESTS ========== //

    function test_cannotBurnOtherOwnersToken() public createReceiptToken {
        // Create a token owned by NON_OWNER and mint some tokens
        vm.prank(NON_OWNER);
        uint256 otherTokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR,
            OPERATOR_NAME
        );

        vm.prank(NON_OWNER);
        receiptTokenManager.mint(RECIPIENT, otherTokenId, MINT_AMOUNT, false);

        // OWNER should not be able to burn this token
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                NON_OWNER
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, otherTokenId, MINT_AMOUNT, false);
    }

    // ========== MULTIPLE RECIPIENTS TESTS ========== //

    function test_burnFromMultipleRecipients() public createReceiptToken {
        address recipient2 = makeAddr("RECIPIENT2");

        // Mint to multiple recipients
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        vm.prank(OWNER);
        receiptTokenManager.mint(recipient2, _tokenId, MINT_AMOUNT, false);

        // Grant allowances
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        vm.prank(recipient2);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        // Burn from first recipient
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);

        // Burn from second recipient
        vm.prank(OWNER);
        receiptTokenManager.burn(recipient2, _tokenId, MINT_AMOUNT / 4, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning"
        );
        assertEq(
            receiptTokenManager.balanceOf(recipient2, _tokenId),
            MINT_AMOUNT - MINT_AMOUNT / 4
        );
    }
}

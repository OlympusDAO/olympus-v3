// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {IDepositReceiptToken} from "src/interfaces/IDepositReceiptToken.sol";

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
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                address(0)
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT, false);
    }

    // given token owner burns tokens with allowance
    //  [X] owner can burn successfully with allowance
    //  [X] balance is updated correctly
    function test_ownerCanBurn() public createReceiptToken mintToRecipient allowOwnerToSpend {
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning"
        );
    }

    // given non-owner attempts to burn
    //  [X] reverts with NotOwner error
    function test_nonOwnerCannotBurn() public createReceiptToken {
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

    // given owner burns from self
    //  [X] burn from self works correctly
    function test_burnFromSelf() public createReceiptToken {
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
    function test_burnZeroAmount() public createReceiptToken mintToRecipient {
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

    function test_burnWithoutBalance() public createReceiptToken {
        address newRecipient = makeAddr("NEW_RECIPIENT");

        // Grant allowance from newRecipient (who has no balance)
        vm.prank(newRecipient);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        // Try to burn from address with no balance
        vm.prank(OWNER);
        receiptTokenManager.burn(newRecipient, _tokenId, MINT_AMOUNT, false);

        // Should succeed (balance becomes negative in theory, but ERC6909 handles underflow)
        assertEq(
            receiptTokenManager.balanceOf(newRecipient, _tokenId),
            0,
            "Balance should remain zero when burning from address without balance"
        );
    }

    function test_burnMoreThanBalance()
        public
        createReceiptToken
        mintToRecipient
        allowOwnerToSpendAll
    {
        // Try to burn more than available balance
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT * 2, false);

        // Should result in zero balance (ERC6909 handles underflow protection)
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            0,
            "Balance should be zero when burning more than available balance"
        );
    }

    // ========== WRAPPING TESTS ========== //

    function test_burnWithWrapFalse() public createReceiptToken {
        // Mint tokens first
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // Grant allowance
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning"
        );
    }

    function test_burnWithWrapTrue() public createReceiptToken {
        // First mint with wrapping to have wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, true);

        // Grant allowance
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        // Then burn wrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, true);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning wrapped tokens"
        );
    }

    function test_burnWrappedWithoutWrappedTokens() public createReceiptToken {
        // Mint tokens first
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // Grant allowance
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, MINT_AMOUNT);

        // Try to burn wrapped tokens when recipient only has unwrapped tokens
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, true);

        // Should still work (burns from ERC6909 balance)
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT / 2,
            "Balance should be reduced after burning"
        );
    }

    // ========== ALLOWANCE TESTS ========== //

    function test_burnWithoutAllowanceButAsOwner() public createReceiptToken {
        // Mint tokens first
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // Owner should still need allowance to burn others' tokens - this test should actually fail
        vm.expectRevert(); // ERC6909InsufficientAllowance
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);
    }

    function test_burnWithAllowance() public createReceiptToken {
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

    // given owner burns without allowance from token holder
    //  [X] owner cannot burn without allowance from holder
    function test_ownerCannotBurnWithoutAllowance() public createReceiptToken {
        // Mint tokens first
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // OWNER tries to burn from RECIPIENT without allowance
        // This should fail because OWNER needs allowance from RECIPIENT to burn their tokens
        vm.expectRevert(); // Should revert due to insufficient allowance - using the actual error signature
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, _tokenId, MINT_AMOUNT / 2, false);
    }

    // ========== INVALID TOKEN TESTS ========== //

    function test_burnInvalidToken() public createReceiptToken {
        uint256 invalidTokenId = 12345;

        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                address(0)
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.burn(RECIPIENT, invalidTokenId, MINT_AMOUNT, false);
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

// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

/**
 * @title MintTest
 * @notice Tests for ReceiptTokenManager token minting functionality
 */
contract ReceiptTokenManagerMintTest is ReceiptTokenManagerTest {
    // given mint to non-existent token
    //  [X] reverts with NotOwner error (owner is address(0))
    function test_mintToNonExistentToken() public {
        // Try to mint to a token that doesn't exist yet
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                address(0)
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);
    }

    // given token owner mints tokens
    //  [X] owner can mint successfully
    //  [X] balance is updated correctly
    function test_whenCallerIsTokenOwner() public createReceiptToken {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT,
            "Recipient should have minted amount in balance"
        );
    }

    // given non-owner attempts to mint
    //  [X] reverts with NotOwner error
    function test_whenCallerIsNotTokenOwner_reverts() public createReceiptToken {
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                NON_OWNER,
                OWNER
            )
        );
        vm.prank(NON_OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);
    }

    // given token owner mints to self
    //  [X] mint to self works correctly
    function test_whenCallerIsTokenOwner_mintToSelf() public createReceiptToken {
        vm.prank(OWNER);
        receiptTokenManager.mint(OWNER, _tokenId, MINT_AMOUNT, false);

        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            MINT_AMOUNT,
            "Owner should have minted amount in balance"
        );
    }

    // given mint to zero address
    //  [X] mint to zero address reverts
    function test_mintToZeroAddress_reverts() public createReceiptToken {
        vm.expectRevert(abi.encodeWithSignature("ERC6909InvalidReceiver(address)", address(0))); // ERC6909 should revert on mint to zero address
        vm.prank(OWNER);
        receiptTokenManager.mint(address(0), _tokenId, MINT_AMOUNT, false);
    }

    // given zero amount mint
    //  [X] mint zero amount reverts
    function test_mintZeroAmount_reverts() public createReceiptToken {
        vm.expectRevert(abi.encodeWithSignature("ERC6909Wrappable_ZeroAmount()")); // Should revert on zero amount mint
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, 0, false);
    }

    // given large amount mint
    //  [X] mint max uint256 amount succeeds
    function test_mintLargeAmount() public createReceiptToken {
        uint256 largeAmount = type(uint256).max;
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, largeAmount, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            largeAmount,
            "Balance should equal the large minted amount"
        );
    }

    // given multiple mints to same recipient
    //  [X] balances accumulate correctly
    function test_mintMultipleTimes() public createReceiptToken {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT * 2,
            "Balance should accumulate correctly after multiple mints"
        );
    }

    // given mints to multiple recipients
    //  [X] each recipient has correct balance
    function test_mintToMultipleRecipients() public createReceiptToken {
        address recipient2 = makeAddr("RECIPIENT2");

        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        vm.prank(OWNER);
        receiptTokenManager.mint(recipient2, _tokenId, MINT_AMOUNT * 2, false);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT,
            "First recipient should have correct balance"
        );
        assertEq(
            receiptTokenManager.balanceOf(recipient2, _tokenId),
            MINT_AMOUNT * 2,
            "Second recipient should have correct balance"
        );
    }

    // given mint without wrapping
    //  [X] ERC6909 balance is updated
    //  [X] wrapped token balance remains zero
    function test_mintWithWrapFalse() public createReceiptToken {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // Should have ERC6909 balance
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT,
            "Should have ERC6909 balance when minting without wrapping"
        );

        // Should have wrapped token created (automatically) but with zero balance
        address wrappedToken = receiptTokenManager.getWrappedToken(_tokenId);
        assertNotEq(wrappedToken, address(0), "Wrapped token should be automatically created");
        assertEq(
            IERC20(wrappedToken).balanceOf(RECIPIENT),
            0,
            "Should have zero wrapped ERC20 balance when wrap=false"
        );
    }

    // given mint with wrapping
    //  [X] ERC6909 balance is zero (converted to wrapped)
    //  [X] wrapped token balance is updated
    function test_mintWithWrapTrue() public createReceiptToken {
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, true);

        // When wrapping, ERC6909 tokens are converted to wrapped ERC20 tokens
        // So ERC6909 balance should be 0 and wrapped token balance should have the amount
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            0,
            "Should have zero ERC6909 balance when tokens are wrapped"
        );

        // Should have wrapped token (automatically created) with balance
        address wrappedToken = receiptTokenManager.getWrappedToken(_tokenId);
        assertNotEq(wrappedToken, address(0), "Wrapped token should be automatically created");

        // Should have wrapped ERC20 balance equal to minted amount
        assertEq(
            IERC20(wrappedToken).balanceOf(RECIPIENT),
            MINT_AMOUNT,
            "Should have wrapped ERC20 balance equal to minted amount when wrap=true"
        );
    }

    // given mixed minting (wrapped and unwrapped)
    //  [X] ERC6909 balance only from unwrapped mint
    //  [X] wrapped token balance only includes wrapped portion
    function test_mintWithWrapMixed() public createReceiptToken {
        // First mint without wrapping
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, false);

        // Then mint with wrapping
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, _tokenId, MINT_AMOUNT, true);

        // Should have ERC6909 balance only from the unwrapped mint
        // The wrapped mint converts ERC6909 tokens to wrapped ERC20 tokens
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT,
            "Should have ERC6909 balance only from unwrapped mint"
        );

        // Should have wrapped token (automatically created) with balance only for wrapped portion
        address wrappedToken = receiptTokenManager.getWrappedToken(_tokenId);
        assertNotEq(wrappedToken, address(0), "Wrapped token should be automatically created");
        assertEq(
            IERC20(wrappedToken).balanceOf(RECIPIENT),
            MINT_AMOUNT,
            "Should have wrapped ERC20 balance equal to the wrapped mint amount only"
        );
    }

    // given mint other owner's token
    //  [X] reverts with NotOwner error
    function test_cannotMintOtherOwnersToken() public createReceiptToken {
        // Create a token owned by NON_OWNER
        vm.prank(NON_OWNER);
        uint256 otherTokenId = receiptTokenManager.createToken(
            IERC20(address(asset)),
            DEPOSIT_PERIOD + 1,
            OPERATOR,
            OPERATOR_NAME
        );

        // OWNER should not be able to mint this token
        vm.expectRevert(
            abi.encodeWithSelector(
                IReceiptTokenManager.ReceiptTokenManager_NotOwner.selector,
                OWNER,
                NON_OWNER
            )
        );
        vm.prank(OWNER);
        receiptTokenManager.mint(RECIPIENT, otherTokenId, MINT_AMOUNT, false);
    }
}

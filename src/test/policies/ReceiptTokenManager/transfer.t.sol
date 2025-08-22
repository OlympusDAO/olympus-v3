// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {ReceiptTokenManagerTest} from "./ReceiptTokenManagerTest.sol";

/**
 * @title TransferTest
 * @notice Tests for ReceiptTokenManager ERC6909 token transfer functionality
 */
contract ReceiptTokenManagerTransferTest is ReceiptTokenManagerTest {
    address internal SPENDER;

    function setUp() public override {
        super.setUp();
        SPENDER = makeAddr("SPENDER");
    }

    // ========== TRANSFER TESTS ========== //

    // given valid transfer parameters
    //  [X] transfers tokens successfully
    //  [X] updates balances correctly
    //  [X] emits Transfer event
    //  [X] does not require allowance (self transfer)
    function test_transferSuccess() public createReceiptToken mintToRecipient {
        uint256 transferAmount = 50e18;

        // Check initial balances
        uint256 recipientBalanceBefore = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);
        uint256 ownerBalanceBefore = receiptTokenManager.balanceOf(OWNER, _tokenId);

        // Perform transfer (no allowance needed for self transfer)
        vm.prank(RECIPIENT);
        vm.expectEmit(true, true, true, true);
        emit Transfer(RECIPIENT, OWNER, _tokenId, transferAmount);
        receiptTokenManager.transfer(OWNER, _tokenId, transferAmount);

        // Check balances after transfer
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            recipientBalanceBefore - transferAmount,
            "Recipient balance should decrease by transfer amount"
        );
        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            ownerBalanceBefore + transferAmount,
            "Owner balance should increase by transfer amount"
        );
    }

    // given transfer to self
    //  [X] transfer succeeds but balance remains the same
    //  [X] does not require allowance
    function test_transferToSelf() public createReceiptToken mintToRecipient {
        uint256 transferAmount = 50e18;
        uint256 balanceBefore = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);

        // No allowance needed for self transfer
        vm.prank(RECIPIENT);
        receiptTokenManager.transfer(RECIPIENT, _tokenId, transferAmount);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            balanceBefore,
            "Balance should remain the same when transferring to self"
        );
    }

    // given transfer of zero amount
    //  [X] transfer succeeds with no balance changes
    function test_transferZeroAmount() public createReceiptToken mintToRecipient {
        uint256 recipientBalanceBefore = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);
        uint256 ownerBalanceBefore = receiptTokenManager.balanceOf(OWNER, _tokenId);

        vm.prank(RECIPIENT);
        receiptTokenManager.transfer(OWNER, _tokenId, 0);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            recipientBalanceBefore,
            "Recipient balance should not change for zero transfer"
        );
        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            ownerBalanceBefore,
            "Owner balance should not change for zero transfer"
        );
    }

    // given insufficient balance
    //  [X] reverts with ERC6909InsufficientBalance
    function test_transferInsufficientBalance_reverts() public createReceiptToken mintToRecipient {
        uint256 balance = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);
        uint256 transferAmount = balance + 1;

        expectInsufficientBalance(RECIPIENT, balance, transferAmount);
        vm.prank(RECIPIENT);
        receiptTokenManager.transfer(OWNER, _tokenId, transferAmount);
    }

    // given transfer to zero address
    //  [X] reverts with ERC6909InvalidReceiver
    function test_transferToZeroAddress_reverts() public createReceiptToken mintToRecipient {
        uint256 transferAmount = 50e18;

        expectInvalidReceiver(address(0));

        vm.prank(RECIPIENT);
        receiptTokenManager.transfer(address(0), _tokenId, transferAmount);
    }

    // given transfer of entire balance
    //  [X] transfer succeeds
    //  [X] sender balance becomes zero
    function test_transferEntireBalance() public createReceiptToken mintToRecipient {
        uint256 entireBalance = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);

        vm.prank(RECIPIENT);
        receiptTokenManager.transfer(OWNER, _tokenId, entireBalance);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            0,
            "Recipient balance should be zero after transferring entire balance"
        );
        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            entireBalance,
            "Owner should receive entire balance"
        );
    }

    // ========== TRANSFERFROM TESTS ========== //

    // given valid transferFrom with allowance
    //  [X] transfers tokens successfully
    //  [X] updates balances correctly
    //  [X] reduces allowance
    //  [X] emits Transfer event
    function test_transferFromWithAllowance()
        public
        createReceiptToken
        mintToRecipient
        allowOwnerToSpend
    {
        uint256 transferAmount = 50e18;
        address recipient2 = makeAddr("recipient2");

        // Check initial state
        uint256 recipientBalanceBefore = receiptTokenManager.balanceOf(RECIPIENT, _tokenId);
        uint256 recipient2BalanceBefore = receiptTokenManager.balanceOf(recipient2, _tokenId);
        uint256 allowanceBefore = receiptTokenManager.allowance(RECIPIENT, OWNER, _tokenId);

        // Perform transferFrom
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit Transfer(RECIPIENT, recipient2, _tokenId, transferAmount);
        receiptTokenManager.transferFrom(RECIPIENT, recipient2, _tokenId, transferAmount);

        // Check balances after transfer
        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            recipientBalanceBefore - transferAmount,
            "Recipient balance should decrease by transfer amount"
        );
        assertEq(
            receiptTokenManager.balanceOf(recipient2, _tokenId),
            recipient2BalanceBefore + transferAmount,
            "Recipient2 balance should increase by transfer amount"
        );
        assertEq(
            receiptTokenManager.allowance(RECIPIENT, OWNER, _tokenId),
            allowanceBefore - transferAmount,
            "Allowance should decrease by transfer amount"
        );
    }

    // given transferFrom without allowance
    //  [X] reverts with ERC6909InsufficientAllowance
    function test_transferFromWithoutAllowance_reverts() public createReceiptToken mintToRecipient {
        uint256 transferAmount = 50e18;

        expectInsufficientAllowance(OWNER, 0, transferAmount);
        vm.prank(OWNER);
        receiptTokenManager.transferFrom(RECIPIENT, OWNER, _tokenId, transferAmount);
    }

    // given transferFrom with insufficient allowance
    //  [X] reverts with ERC6909InsufficientAllowance
    function test_transferFromInsufficientAllowance_reverts()
        public
        createReceiptToken
        mintToRecipient
    {
        uint256 allowanceAmount = 30e18;
        uint256 transferAmount = 50e18;

        // Set insufficient allowance
        vm.prank(RECIPIENT);
        receiptTokenManager.approve(OWNER, _tokenId, allowanceAmount);

        expectInsufficientAllowance(OWNER, allowanceAmount, transferAmount);
        vm.prank(OWNER);
        receiptTokenManager.transferFrom(RECIPIENT, OWNER, _tokenId, transferAmount);
    }

    // given transferFrom with unlimited allowance
    //  [X] transfer succeeds
    //  [X] allowance remains unlimited
    function test_transferFromUnlimitedAllowance()
        public
        createReceiptToken
        mintToRecipient
        allowOwnerToSpendAll
    {
        uint256 transferAmount = 50e18;

        // Check initial allowance is unlimited
        assertEq(
            receiptTokenManager.allowance(RECIPIENT, OWNER, _tokenId),
            type(uint256).max,
            "Initial allowance should be unlimited"
        );

        vm.prank(OWNER);
        receiptTokenManager.transferFrom(RECIPIENT, OWNER, _tokenId, transferAmount);

        // Check allowance remains unlimited
        assertEq(
            receiptTokenManager.allowance(RECIPIENT, OWNER, _tokenId),
            type(uint256).max,
            "Allowance should remain unlimited after transfer"
        );
    }

    // given self transferFrom (owner transferring their own tokens)
    //  [X] transfer succeeds without allowance
    function test_transferFromSelfNoAllowance() public createReceiptToken mintToRecipient {
        uint256 transferAmount = 50e18;

        // No need to set allowance for self transfers
        vm.prank(RECIPIENT);
        receiptTokenManager.transferFrom(RECIPIENT, OWNER, _tokenId, transferAmount);

        assertEq(
            receiptTokenManager.balanceOf(RECIPIENT, _tokenId),
            MINT_AMOUNT - transferAmount,
            "Recipient balance should decrease by transfer amount"
        );
        assertEq(
            receiptTokenManager.balanceOf(OWNER, _tokenId),
            transferAmount,
            "Owner balance should increase by transfer amount"
        );
    }

    // Events for testing
    event Transfer(address indexed from, address indexed to, uint256 indexed id, uint256 amount);
}

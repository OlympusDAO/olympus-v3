// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @notice Safe ERC20 and ETH transfer library that safely handles missing return values.
/// @author Modified from Uniswap & old Solmate (https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/TransferHelper.sol)
library TransferHelper {
    /// @notice A transfer delivered a different amount than requested.
    /// @param token Token transferred.
    /// @param recipient Account expected to receive the transfer.
    /// @param expectedAmount Amount requested from the sender.
    /// @param receivedAmount Increase in the recipient's balance, or zero if its balance decreased.
    error TransferHelper_InexactTransferFrom(
        address token,
        address recipient,
        uint256 expectedAmount,
        uint256 receivedAmount
    );

    /// @notice Safely transfers tokens from one account to another.
    /// @dev Reverts when the token call fails or returns false.
    function safeTransferFrom(ERC20 token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.transferFrom.selector, from, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    /// @notice Safely transfers tokens and verifies the recipient's exact balance increase.
    /// @dev Reverts when the token call fails, returns false, decreases the recipient's balance, or
    ///      delivers an amount different from `amount`.
    /// @return recipientBalanceBefore Recipient balance immediately before the transfer.
    function safeTransferFromExact(
        ERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 recipientBalanceBefore) {
        recipientBalanceBefore = token.balanceOf(to);
        safeTransferFrom(token, from, to, amount);
        uint256 recipientBalanceAfter = token.balanceOf(to);
        if (recipientBalanceAfter < recipientBalanceBefore) {
            revert TransferHelper_InexactTransferFrom(address(token), to, amount, 0);
        }
        uint256 receivedAmount;
        unchecked {
            receivedAmount = recipientBalanceAfter - recipientBalanceBefore;
        }
        if (receivedAmount != amount) {
            revert TransferHelper_InexactTransferFrom(address(token), to, amount, receivedAmount);
        }
    }

    /// @notice Safely transfers tokens to an account.
    /// @dev Reverts when the token call fails or returns false.
    function safeTransfer(ERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.transfer.selector, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @notice Safely sets a token allowance.
    /// @dev Reverts when the token call fails or returns false.
    function safeApprove(ERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.approve.selector, to, amount)
        );

        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }
}

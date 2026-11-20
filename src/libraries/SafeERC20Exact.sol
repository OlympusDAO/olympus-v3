// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";

// Libraries
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";

/// @notice Exact-receipt extension for OpenZeppelin SafeERC20.
library SafeERC20Exact {
    /// @notice The recipient received a different number of tokens than requested.
    /// @param token Token transferred.
    /// @param recipient Account expected to receive the transfer.
    /// @param expectedAmount Amount requested from the sender.
    /// @param receivedAmount Increase in the recipient's balance, or zero if it decreased.
    error SafeERC20Exact_InexactTransferFrom(
        address token,
        address recipient,
        uint256 expectedAmount,
        uint256 receivedAmount
    );

    /// @notice Transfers tokens and verifies the recipient's exact balance increase.
    /// @dev Reverts if the transfer fails or credits an amount other than `amount_`.
    /// @param token_ Token transferred.
    /// @param from_ Sender whose tokens are transferred.
    /// @param to_ Recipient whose balance increase is checked.
    /// @param amount_ Requested transfer amount.
    /// @return recipientBalanceBefore Recipient balance immediately before the transfer.
    function safeTransferFromExact(
        IERC20 token_,
        address from_,
        address to_,
        uint256 amount_
    ) internal returns (uint256 recipientBalanceBefore) {
        recipientBalanceBefore = token_.balanceOf(to_);
        SafeERC20.safeTransferFrom(token_, from_, to_, amount_);
        uint256 recipientBalanceAfter = token_.balanceOf(to_);
        if (recipientBalanceAfter < recipientBalanceBefore) {
            revert SafeERC20Exact_InexactTransferFrom(address(token_), to_, amount_, 0);
        }
        uint256 receivedAmount;
        unchecked {
            receivedAmount = recipientBalanceAfter - recipientBalanceBefore;
        }
        if (receivedAmount != amount_) {
            revert SafeERC20Exact_InexactTransferFrom(
                address(token_),
                to_,
                amount_,
                receivedAmount
            );
        }
    }
}

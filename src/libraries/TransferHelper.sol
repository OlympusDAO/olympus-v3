// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

/// @notice Safe ERC20 and ETH transfer library that safely handles missing return values.
/// @author Modified from Uniswap & old Solmate (https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/TransferHelper.sol)
library TransferHelper {
    /// @notice Safely transfers tokens from one account to another.
    /// @dev Reverts when the token call fails or returns false.
    function safeTransferFrom(ERC20 token, address from, address to, uint256 amount) internal {
        // Low-level token calls support optional ERC-20 return values.
        // forge-lint: disable-start(low-level-calls)
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.transferFrom.selector, from, to, amount)
        );
        // forge-lint: disable-end(low-level-calls)

        // Preserve the helper's legacy failure ABI.
        // forge-lint: disable-next-line(custom-errors)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    /// @notice Safely transfers tokens to an account.
    /// @dev Reverts when the token call fails or returns false.
    function safeTransfer(ERC20 token, address to, uint256 amount) internal {
        // Each batch transfer needs its own token call; optional return values remain supported.
        // forge-lint: disable-start(low-level-calls,calls-loop)
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.transfer.selector, to, amount)
        );
        // forge-lint: disable-end(low-level-calls,calls-loop)

        // Preserve the legacy failure ABI, including when callers transfer inside a loop.
        // forge-lint: disable-next-line(custom-errors,require-revert-in-loop)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @notice Safely sets a token allowance.
    /// @dev Reverts when the token call fails or returns false.
    function safeApprove(ERC20 token, address to, uint256 amount) internal {
        // Low-level token calls support optional ERC-20 return values.
        // forge-lint: disable-start(low-level-calls)
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(ERC20.approve.selector, to, amount)
        );
        // forge-lint: disable-end(low-level-calls)

        // Preserve the helper's legacy failure ABI.
        // forge-lint: disable-next-line(custom-errors)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }
}

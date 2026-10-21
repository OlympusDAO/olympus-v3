// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Libraries
import {IERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeERC20Exact} from "src/libraries/SafeERC20Exact.sol";

contract SafeERC20Harness {
    using SafeERC20 for IERC20;
    using SafeERC20Exact for IERC20;

    /// @notice Pulls an exact token amount into `recipient_` for testing.
    function safeTransferFromExact(
        IERC20 token_,
        address sender_,
        address recipient_,
        uint256 amount_
    ) external returns (uint256 recipientBalanceBefore_) {
        return token_.safeTransferFromExact(sender_, recipient_, amount_);
    }

    /// @notice Attempts an optional transfer for testing.
    function trySafeTransfer(
        IERC20 token_,
        address recipient_,
        uint256 amount_
    ) external returns (bool) {
        return token_.trySafeTransfer(recipient_, amount_);
    }
}

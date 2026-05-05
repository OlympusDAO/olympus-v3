// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.18;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IRescuable} from "src/interfaces/IRescuable.sol";

// Libraries
import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";

/// @title Rescuable
/// @notice Abstract base for contracts that expose a privileged `rescue()` to sweep
///         accidentally-sent assets. Subclasses authenticate the caller via the
///         `_authenticateRescue()` hook.
/// @dev Native token (ETH) is identified using the EIP-7528 sentinel address
///      (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`), which is unambiguous and
///      will never collide with a deployed ERC20.
abstract contract Rescuable is IRescuable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IRescuable
    address public constant override NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @inheritdoc IRescuable
    function rescue(address token_, address payable to_) external virtual override {
        _authenticateRescue();

        if (to_ == address(0)) revert Rescuable_InvalidRecipient();

        uint256 balance;
        if (token_ == NATIVE_TOKEN) {
            balance = address(this).balance;
            Address.sendValue(to_, balance);
        } else {
            balance = IERC20(token_).balanceOf(address(this));
            IERC20(token_).safeTransfer(to_, balance);
        }

        emit Rescued(token_, to_, balance);
    }

    /// @notice Hook for subclasses to authenticate the caller of `rescue()`.
    /// @dev Implementations MUST revert if the caller is not authorised.
    function _authenticateRescue() internal view virtual;
}

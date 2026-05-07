// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IRescueable} from "src/bases/interfaces/IRescueable.sol";

// Libraries
import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ERC7528Constants} from "src/libraries/ERC7528Constants.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";

/// @title Rescueable
/// @notice An abstract base for contracts that expose a privileged `rescue()` to sweep
///         accidentally-sent assets.
///         Derived contracts authorize the caller via the `_authorizeRescue()` hook.
/// @dev Native token is identified using the EIP-7528 sentinel.
abstract contract Rescueable is IRescueable, ERC165 {
    using SafeERC20 for IERC20;

    /// @inheritdoc IRescueable
    address public constant override NATIVE_TOKEN = ERC7528Constants.NATIVE_TOKEN;

    /// @inheritdoc IRescueable
    /// @dev Sweeps the entire balance of the specified asset to the provided recipient.
    ///      Pass `NATIVE_TOKEN` (the EIP-7528 sentinel) as `token_` to rescue the native
    ///      token.
    ///
    ///      Reverts if:
    ///      - The caller is not authorised by the implementation's `_authorizeRescue()`.
    ///      - `to_` is the zero address.
    ///
    ///      Does NOT revert when the contract's balance of `token_` is zero, so the call is
    ///      a no-op apart from the emitted event with `amount == 0`.
    function rescue(address token_, address payable to_) external virtual override {
        _authorizeRescue();

        if (to_ == address(0)) revert Rescueable_InvalidRecipient();

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

    /// @notice Hook for subclasses to authorize the caller of `rescue()`.
    /// @dev Implementations MUST revert if the caller is not authorised.
    function _authorizeRescue() internal view virtual;

    // ========= ERC165 ========= //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IRescueable).interfaceId || super.supportsInterface(interfaceId);
    }
}

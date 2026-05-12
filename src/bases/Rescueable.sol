// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";
import {IRescueable} from "src/bases/interfaces/IRescueable.sol";

// Libraries
import {Address} from "@openzeppelin-5.3.0/utils/Address.sol";
import {SafeERC20} from "@openzeppelin-5.3.0/token/ERC20/utils/SafeERC20.sol";
import {ERC7528Constants} from "src/libraries/ERC7528Constants.sol";
import {Errors} from "src/libraries/Errors.sol";

// Contracts
import {ERC165} from "@openzeppelin-5.3.0/utils/introspection/ERC165.sol";

/// @title Rescueable
/// @notice An abstract base for contracts that expose a privileged `rescue()` to sweep
///         accidentally-sent assets.
///         Derived contracts authorize the caller via the `_authorizeRescue()` hook.
/// @dev The native asset is identified using the EIP-7528 sentinel.
abstract contract Rescueable is IRescueable, ERC165 {
    /// @inheritdoc IRescueable
    /// @dev Sweeps the entire balance of the specified asset to the provided recipient.
    ///      Pass the EIP-7528 native sentinel (`ERC7528Constants.NATIVE_ASSET`) as `token_`
    ///      to rescue the native asset.
    ///
    ///      Reverts if:
    ///      - The caller is not authorised by the implementation's `_authorizeRescue()`.
    ///      - `to_` is the zero address.
    ///
    ///      Does NOT revert when the contract's balance of `token_` is zero, so the call is
    ///      a no-op in that case.
    function rescue(address token_, address payable to_) public virtual override {
        _authorizeRescue();

        if (to_ == address(0)) revert Errors.InvalidRecipient();

        if (token_ == ERC7528Constants.NATIVE_ASSET) {
            Address.sendValue(to_, address(this).balance);
        } else {
            SafeERC20.safeTransfer(IERC20(token_), to_, IERC20(token_).balanceOf(address(this)));
        }
    }

    /// @notice Hook for subclasses to authorize the caller of `rescue()`.
    /// @dev Implementations MUST revert if the caller is not authorised.
    function _authorizeRescue() internal view virtual;

    // ========= ERC165 ========= //

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IRescueable).interfaceId || super.supportsInterface(interfaceId);
    }
}

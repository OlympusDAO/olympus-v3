// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

// Interfaces
import {IEnablerV2GracePeriod} from "src/interfaces/IEnablerV2GracePeriod.sol";

// Contracts
import {EnablerV2} from "src/libraries/EnablerV2.sol";

/// @title EnablerV2GracePeriod
/// @notice An abstract extension of `EnablerV2` that exposes a fixed grace window
///         measured from the most recent transition timestamp.
/// @dev The extension does not gate `enable`, `disable`, or any other entry
///      point on its own. Inheriting contracts opt in to the grace check by
///      invoking `_requireGrace` from the appropriate authorization or
///      lifecycle hook, typically a privileged action that should only be
///      available within the window that follows a transition.
///
///      The grace window restarts on every transition recorded by
///      `EnablerV2`, so a fresh transition opens a new window of the same length.
abstract contract EnablerV2GracePeriod is IEnablerV2GracePeriod, EnablerV2 {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IEnablerV2GracePeriod
    /// @dev The value is set at construction time and cannot be changed afterwards,
    ///      and is the length of the window measured from
    ///      `IEnablerV2.lastTransitionAt`, so a fresh transition restarts the
    ///      window at its full length.
    uint32 public immutable override GRACE;

    // ========== INITIALIZATION ========== //

    /// @notice Configures the grace window with the supplied length in seconds.
    /// @dev A zero window would prevent any grace-gated operation from
    ///      succeeding and is therefore rejected at construction time.
    ///
    ///      Reverts if:
    ///      - `p_` is zero.
    /// @param p_ The length of the grace window in seconds.
    constructor(uint32 p_) {
        if (p_ == 0) revert EnablerV2GracePeriod_ZeroPeriod();
        GRACE = p_;
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Asserts that the grace window measured from `lastTransitionAt`
    ///         has not yet elapsed.
    /// @dev The deadline is computed as `lastTransitionAt + GRACE`, and the
    ///      check passes when the current timestamp is less than or equal
    ///      to that deadline. The function is virtual so that inheriting
    ///      contracts can extend or replace the deadline calculation.
    ///
    ///      Reverts if:
    ///      - The current timestamp is strictly greater than the computed deadline.
    function _requireGrace() internal view virtual {
        uint48 deadline = lastTransitionAt + GRACE;
        if (_getBlockTimestamp() > deadline)
            revert EnablerV2GracePeriod_GracePeriodExpired(deadline);
    }

    // ========== ERC-165 ========== //

    /// @inheritdoc EnablerV2
    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IEnablerV2GracePeriod).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}

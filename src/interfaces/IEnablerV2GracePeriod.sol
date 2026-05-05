// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";

/// @title IEnablerV2GracePeriod
/// @notice The external interface of a grace period extension for an `IEnablerV2`
///         implementation, which exposes the configured grace window and the errors
///         related to its configuration and enforcement.
interface IEnablerV2GracePeriod is IEnablerV2 {
    // ========== ERRORS ========== //

    /// @notice Thrown when an operation gated by the grace window is invoked after the
    ///         window has elapsed.
    /// @param deadline The timestamp at which the grace window ended.
    error EnablerV2GracePeriod_GracePeriodExpired(uint48 deadline);

    /// @notice Thrown when the implementation contract is constructed with a zero
    ///         grace window, which would otherwise prevent any grace-gated operation
    ///         from succeeding.
    error EnablerV2GracePeriod_ZeroPeriod();

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the configured grace window in seconds.
    /// @return period The length of the grace window in seconds.
    function GRACE() external view returns (uint32 period);
}

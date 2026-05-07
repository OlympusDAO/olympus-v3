// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGracePeriod
/// @notice The external interface of a contract that exposes a fixed grace window measured
///         from a reference timestamp, along with the errors related to its configuration
///         and enforcement.
interface IGracePeriod {
    // ========== ERRORS ========== //

    /// @notice Thrown when an operation gated by the grace window is invoked after the
    ///         window has elapsed.
    /// @param deadline The timestamp at which the grace window ended.
    error GracePeriod_Expired(uint48 deadline);

    /// @notice Thrown when the implementation contract is constructed with a zero
    ///         grace window, which would otherwise prevent any grace-gated operation
    ///         from succeeding.
    error GracePeriod_ZeroPeriod();

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the configured grace window in seconds.
    /// @return period The length of the grace window in seconds.
    function gracePeriod() external view returns (uint32 period);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGracePeriod
/// @notice The external interface of a contract that exposes a grace window measured from
///         a reference timestamp, along with the events and errors related to its
///         configuration and enforcement.
interface IGracePeriod {
    // ========== EVENTS ========== //

    /// @notice Emitted when the grace window is configured.
    /// @param period The new length of the grace window in seconds.
    event GracePeriodSet(uint32 period);

    // ========== ERRORS ========== //

    /// @notice Thrown when an operation gated by the grace window is invoked after the
    ///         window has elapsed.
    /// @param deadline The timestamp at which the grace window ended.
    error GracePeriod_Expired(uint48 deadline);

    /// @notice Thrown when the grace window is configured with a zero length, which would
    ///         otherwise prevent any grace-gated operation from succeeding.
    error GracePeriod_ZeroPeriod();

    /// @notice Thrown when a call to `setGracePeriod` is rejected because the
    ///         implementation has locked the grace window.
    error GracePeriod_NotConfigurable();

    // ========== STATE-CHANGING FUNCTIONS ========== //

    /// @notice Updates the grace window to the supplied length in seconds.
    /// @param period_ The new length of the grace window in seconds.
    function setGracePeriod(uint32 period_) external;

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the configured grace window in seconds.
    /// @return period The length of the grace window in seconds.
    function gracePeriod() external view returns (uint32 period);
}

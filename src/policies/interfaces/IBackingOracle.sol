// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title IBackingOracle
/// @notice The interface for the BackingOracle policy, which serves as the canonical OHM backing value.
/// @dev Backing updates are timelocked. A proposer queues an update via `queueSetBacking`, and the
///      update is applied when the queued action is executed through the `ITimelockQueue` surface
///      implemented by the policy. The admin role can additionally update the backing directly via
///      `setBacking`, without the timelock.
interface IBackingOracle {
    // ============ EVENTS ============ //

    /// @notice Emitted when the backing value is updated.
    /// @param newBacking The new backing value (18 decimals).
    event BackingSet(uint256 newBacking);

    // ============ ERRORS ============ //

    /// @notice Thrown when the constructor receives a zero kernel address.
    error BackingOracle_ZeroKernelAddress();

    /// @notice Thrown when the enable data length does not match the expected 32 bytes (one uint256).
    error BackingOracle_InvalidEnableDataLength();

    /// @notice Thrown when the new backing value is zero.
    error BackingOracle_ZeroBacking();

    /// @notice Thrown when the new backing value changes the current backing beyond the allowed threshold.
    /// @param currentBacking The current backing value.
    /// @param newBacking The proposed new backing value.
    /// @param minBacking The minimum allowed backing value.
    /// @param maxBacking The maximum allowed backing value.
    error BackingOracle_BackingChangeTooLarge(
        uint256 currentBacking,
        uint256 newBacking,
        uint256 minBacking,
        uint256 maxBacking
    );

    // ============ TIMELOCK MANAGEMENT ============ //

    /// @notice Queue a timelocked change to the timelock delay.
    /// @dev The delay update is not applied until the queued action is executed. Intended to be
    ///      callable only by the admin role.
    ///
    /// @param delay_ The new timelock delay in seconds.
    /// @return actionId_ The queued action ID.
    function queueTimelockDelay(uint48 delay_) external returns (uint64 actionId_);

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Set the backing value (the reserve per OHM, 18 decimals).
    /// @dev The value is applied without the local timelock queue; the backing change threshold
    ///      still applies. Intended to be callable only by the admin role, which is expected to
    ///      be held only by the OCG timelock, so the function is de-facto timelocked.
    ///
    /// @param newBacking_ The new backing value (18 decimals).
    function setBacking(uint256 newBacking_) external;

    /// @notice Queue a timelocked update of the backing value (the reserve per OHM, 18 decimals).
    /// @dev The backing value is not updated until the queued action is executed. The backing
    ///      change threshold is validated against the current backing value both when the action
    ///      is queued and when it is executed, because the current backing may change between the
    ///      two. Intended to be callable only by the backing_admin or admin role.
    ///
    /// @param newBacking_ The new backing value (18 decimals).
    /// @return actionId_ The queued action ID.
    function queueSetBacking(uint256 newBacking_) external returns (uint64 actionId_);

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the current OHM backing value (the reserve per OHM, 18 decimals).
    /// @return The current backing value (18 decimals).
    function backing() external view returns (uint256);
}

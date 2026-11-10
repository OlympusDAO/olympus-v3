// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBackingOracle
/// @notice The interface for the BackingOracle policy, which serves as the canonical OHM backing value.
/// @dev ADMIN or the selected config operator can apply bounded updates. A separate
///      BackingOracleConfigTimelock supplies the operational proposal delay.
interface IBackingOracle {
    // ============ EVENTS ============ //

    /// @notice Emitted when the backing value is updated.
    /// @param newBacking The new backing value (18 decimals).
    event BackingSet(uint256 newBacking);

    // ============ ERRORS ============ //

    /// @notice Thrown when the constructor receives a zero kernel address.
    error BackingOracle_ZeroKernelAddress();

    /// @notice Thrown when a mutation requires this policy to be active in its Kernel.
    error BackingOracle_PolicyNotActive(address policy);

    /// @notice Thrown when the enable data length does not match the expected 32 bytes (one uint256).
    error BackingOracle_InvalidEnableDataLength();

    /// @notice Thrown when disable receives nonempty data.
    error BackingOracle_InvalidDisableDataLength();

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

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Set the backing value (the reserve per OHM, 18 decimals).
    /// @dev ADMIN and the current nonzero config operator can apply updates. The operator is
    ///      intended to be a configuration timelock; ADMIN is intended to be OCG's timelock.
    ///
    /// @param newBacking_ The new backing value (18 decimals).
    function setBacking(uint256 newBacking_) external;

    /// @notice Validate a proposed backing update against the current oracle state.
    /// @param newBacking_ Proposed backing value (18 decimals).
    function validateSetBacking(uint256 newBacking_) external view;

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the current OHM backing value (the reserve per OHM, in `decimals`
    ///         decimals).
    /// @return The current backing value.
    function backing() external view returns (uint256);

    /// @notice Returns the decimals of the backing value reported by `backing`.
    /// @return The decimals of the backing value.
    function decimals() external view returns (uint8);
}

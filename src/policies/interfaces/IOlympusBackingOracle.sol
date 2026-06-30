// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IOlympusBackingOracle
/// @notice The interface for the OlympusBackingOracle policy, which serves as the canonical OHM backing value.
interface IOlympusBackingOracle {
    // ============ EVENTS ============ //

    /// @notice Emitted when the backing value is updated.
    /// @param newBacking The new backing value (18 decimals).
    event BackingSet(uint256 newBacking);

    // ============ ERRORS ============ //

    /// @notice Thrown when the constructor receives a zero kernel address.
    error OlympusBackingOracle_ZeroKernelAddress();

    /// @notice Thrown when the enable data length does not match the expected 32 bytes (one uint256).
    error OlympusBackingOracle_InvalidEnableDataLength();

    /// @notice Thrown when the new backing value is zero.
    error OlympusBackingOracle_ZeroBacking();

    /// @notice Thrown when the new backing value changes the current backing beyond the allowed threshold.
    /// @param currentBacking The current backing value.
    /// @param newBacking The proposed new backing value.
    /// @param minBacking The minimum allowed backing value.
    /// @param maxBacking The maximum allowed backing value.
    error OlympusBackingOracle_BackingChangeTooLarge(
        uint256 currentBacking,
        uint256 newBacking,
        uint256 minBacking,
        uint256 maxBacking
    );

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Set the backing value (the reserve per OHM, 18 decimals).
    /// @param newBacking_ The new backing value (18 decimals).
    function setBacking(uint256 newBacking_) external;

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Returns the current OHM backing value (the reserve per OHM, 18 decimals).
    /// @return The current backing value (18 decimals).
    function backing() external view returns (uint256);
}

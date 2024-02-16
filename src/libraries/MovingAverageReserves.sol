/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

/// @title      BunniReserves
/// @notice     A library that provides functionality for tracking and updating moving average reserves in a Bunni-managed pool
abstract contract BunniReserves {
    // ============ Errors ============ //

    error MovingAverageStale(address pool_, uint48 lastObservationTime_);

    error Params_LastObservationTimeInvalid(
        address pool_,
        uint48 lastObservationTime_,
        uint48 earliestTimestamp_,
        uint48 latestTimestamp_
    );

    error Params_DurationInvalid(address pool_, uint16 duration_, uint48 frequency_);

    error Params_InvalidObservationCount(address pool_, uint16 numObservations_);

    error Params_ObservationZero(address pool_, uint256 index_);

    // ============ Structs ============ //

    struct MovingAverageConfiguration {
        uint16 nextObservationIndex;
        uint16 numObservations;
        uint48 lastObservationTime;
    }

    struct TokenReserveObservations {
        uint256[] observations;
        uint256 cumulativeObservations;
    }

    // ============ State Variables ============ //

    /// @notice     Configuration of the moving average for a particular pool token
    mapping(address => MovingAverageConfiguration) internal movingAverageConfigurations;

    /// @notice     Observations of the token reserves for a particular pool token
    mapping(address => TokenReserveObservations[]) internal tokenReserveObservations;
}

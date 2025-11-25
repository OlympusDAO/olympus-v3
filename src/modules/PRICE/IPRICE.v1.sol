// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

/// @notice Price oracle interface for PRICEv1
/// @dev    Minimal interface extracted from PRICEv1 abstract contract
interface IPRICEv1 {
    // =========  EVENTS ========= //

    event MinimumTargetPriceChanged(uint256 minimumTargetPrice_);

    // =========  STATE ========= //

    /// @notice Frequency (in seconds) that observations should be stored.
    function observationFrequency() external view returns (uint48);

    /// @notice Unix timestamp of last observation (in seconds).
    function lastObservationTime() external view returns (uint48);

    /// @notice Number of decimals in the price values provided by the contract.
    function decimals() external view returns (uint8);

    /// @notice Minimum target price for RBS system. Set manually to correspond to the liquid backing of OHM.
    function minimumTargetPrice() external view returns (uint256);

    // =========  FUNCTIONS ========= //

    /// @notice Trigger an update of the moving average. Permissioned.
    function updateMovingAverage() external;

    /// @notice Initialize the price module
    function initialize(uint256[] memory startObservations_, uint48 lastObservationTime_) external;

    /// @notice Change the moving average window (duration)
    function changeMovingAverageDuration(uint48 movingAverageDuration_) external;

    /// @notice   Change the observation frequency of the moving average (i.e. how often a new observation is taken)
    function changeObservationFrequency(uint48 observationFrequency_) external;

    /// @notice   Change the update thresholds for the price feeds
    function changeUpdateThresholds(
        uint48 ohmEthUpdateThreshold_,
        uint48 reserveEthUpdateThreshold_
    ) external;

    /// @notice   Change the minimum target price
    function changeMinimumTargetPrice(uint256 minimumTargetPrice_) external;

    /// @notice Get the current price of OHM in the Reserve asset from the price feeds
    function getCurrentPrice() external view returns (uint256);

    /// @notice Get the last stored price observation of OHM in the Reserve asset
    function getLastPrice() external view returns (uint256);

    /// @notice Get the moving average of OHM in the Reserve asset over the defined window (see movingAverageDuration and observationFrequency).
    function getMovingAverage() external view returns (uint256);

    /// @notice Get target price of OHM in the Reserve asset for the RBS system
    function getTargetPrice() external view returns (uint256);
}

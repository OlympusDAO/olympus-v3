// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";
import "src/Kernel.sol";

abstract contract PRICE_V1 is Module {
    // EVENTS
    event NewObservation(uint256 timestamp_, uint256 price_, uint256 movingAverage_);
    event MovingAverageDurationChanged(uint48 movingAverageDuration_);
    event ObservationFrequencyChanged(uint48 observationFrequency_);

    // ERRORS
    error Price_InvalidParams();
    error Price_NotInitialized();
    error Price_AlreadyInitialized();
    error Price_BadFeed(address priceFeed);

    // STATE

    /// @dev    Price feeds. Chainlink typically provides price feeds for an asset in ETH. Therefore, we use two price feeds against ETH, one for OHM and one for the Reserve asset, to calculate the relative price of OHM in the Reserve asset.
    /// @dev    Update thresholds are the maximum amount of time that can pass between price feed updates before the price oracle is considered stale. These should be set based on the parameters of the price feed.

    /// @notice OHM/ETH price feed
    AggregatorV2V3Interface public ohmEthPriceFeed;

    /// @notice Maximum expected time between OHM/ETH price feed updates
    uint48 public ohmEthUpdateThreshold;

    /// @notice Reserve/ETH price feed
    AggregatorV2V3Interface public reserveEthPriceFeed;

    /// @notice Maximum expected time between OHM/ETH price feed updates
    uint48 public reserveEthUpdateThreshold;

    /// @notice    Running sum of observations to calculate the moving average price from
    /// @dev       See getMovingAverage()
    uint256 public cumulativeObs;

    /// @notice Array of price observations. Check nextObsIndex to determine latest data point.
    /// @dev    Observations are stored in a ring buffer where the moving average is the sum of all observations divided by the number of observations.
    ///         Observations can be cleared by changing the movingAverageDuration or observationFrequency and must be re-initialized.
    uint256[] public observations;

    /// @notice Index of the next observation to make. The current value at this index is the oldest observation.
    uint32 public nextObsIndex;

    /// @notice Number of observations used in the moving average calculation. Computed from movingAverageDuration / observationFrequency.
    uint32 public numObservations;

    /// @notice Frequency (in seconds) that observations should be stored.
    uint48 public observationFrequency;

    /// @notice Duration (in seconds) over which the moving average is calculated.
    uint48 public movingAverageDuration;

    /// @notice Unix timestamp of last observation (in seconds).
    uint48 public lastObservationTime;

    /// @notice Whether the price module is initialized (and therefore active).
    bool public initialized;

    // FUNCTIONS
    function updateMovingAverage() external virtual;

    function getCurrentPrice() external virtual returns (uint256);

    function getLastPrice() external virtual returns (uint256);

    function getMovingAverage() external virtual returns (uint256);

    function initialize(uint256[] memory startObservations_, uint48 lastObservationTime_)
        external
        virtual;

    function changeMovingAverageDuration(uint48 movingAverageDuration_) external virtual;

    function changeObservationFrequency(uint48 observationFrequency_) external virtual;
}

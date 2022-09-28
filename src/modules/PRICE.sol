// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import "src/Kernel.sol";

// ERRORS
error Price_InvalidParams();
error Price_NotInitialized();
error Price_AlreadyInitialized();
error Price_BadFeed(address priceFeed);

/// @notice Price oracle data storage contract
/// @dev    The Olympus Price Oracle contract provides a standard interface for OHM price data against a reserve asset.
///         It also implements a moving average price calculation (same as a TWAP) on the price feed data over a configured
///         duration and observation frequency. The data provided by this contract is used by the Olympus Range Operator to
///         perform market operations. The Olympus Price Oracle is updated each epoch by the Olympus Heart contract.
contract OlympusPrice is Module {
    /* ========== EVENTS =========== */
    event NewObservation(uint256 timestamp_, uint256 price_, uint256 movingAverage_);
    event MovingAverageDurationChanged(uint48 movingAverageDuration_);
    event ObservationFrequencyChanged(uint48 observationFrequency_);
    /* ========== STATE VARIABLES ========== */

    /// @dev    Price feeds. Chainlink typically provides price feeds for an asset in ETH. Therefore, we use two price feeds against ETH, one for OHM and one for the Reserve asset, to calculate the relative price of OHM in the Reserve asset.
    /// @dev    Update thresholds are the maximum amount of time that can pass between price feed updates before the price oracle is considered stale. These should be set based on the parameters of the price feed.

    /// @notice OHM/ETH price feed
    AggregatorV2V3Interface public immutable ohmEthPriceFeed;

    /// @notice Maximum expected time between OHM/ETH price feed updates
    uint48 public ohmEthUpdateThreshold;

    /// @notice Reserve/ETH price feed
    AggregatorV2V3Interface public immutable reserveEthPriceFeed;

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

    /// @notice Number of decimals in the price values provided by the contract.
    uint8 public constant decimals = 18;

    /// @notice Whether the price module is initialized (and therefore active).
    bool public initialized;

    // Scale factor for converting prices, calculated from decimal values.
    uint256 internal immutable _scaleFactor;

    /*//////////////////////////////////////////////////////////////
                            MODULE INTERFACE
    //////////////////////////////////////////////////////////////*/

    constructor(
        Kernel kernel_,
        AggregatorV2V3Interface ohmEthPriceFeed_,
        uint48 ohmEthUpdateThreshold_,
        AggregatorV2V3Interface reserveEthPriceFeed_,
        uint48 reserveEthUpdateThreshold_,
        uint48 observationFrequency_,
        uint48 movingAverageDuration_
    ) Module(kernel_) {
        /// @dev Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency_ != 0)
            revert Price_InvalidParams();

        // Set price feeds, decimals, and scale factor
        ohmEthPriceFeed = ohmEthPriceFeed_;
        ohmEthUpdateThreshold = ohmEthUpdateThreshold_;
        uint8 ohmEthDecimals = ohmEthPriceFeed.decimals();

        reserveEthPriceFeed = reserveEthPriceFeed_;
        reserveEthUpdateThreshold = reserveEthUpdateThreshold_;
        uint8 reserveEthDecimals = reserveEthPriceFeed.decimals();

        uint256 exponent = decimals + reserveEthDecimals - ohmEthDecimals;
        if (exponent > 38) revert Price_InvalidParams();
        _scaleFactor = 10**exponent;

        // Set parameters and calculate number of observations
        observationFrequency = observationFrequency_;
        movingAverageDuration = movingAverageDuration_;

        numObservations = uint32(movingAverageDuration_ / observationFrequency_);

        // Store blank observations array
        observations = new uint256[](numObservations);
        // nextObsIndex is initialized to 0

        emit MovingAverageDurationChanged(movingAverageDuration_);
        emit ObservationFrequencyChanged(observationFrequency_);
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /* ========== POLICY FUNCTIONS ========== */

    /// @notice Trigger an update of the moving average. Permissioned.
    /// @dev    This function does not have a time-gating on the observationFrequency on this contract. It is set on the Heart policy contract.
    ///         The Heart beat frequency should be set to the same value as the observationFrequency.
    function updateMovingAverage() external permissioned {
        // Revert if not initialized
        if (!initialized) revert Price_NotInitialized();

        // Cache numbe of observations to save gas.
        uint32 numObs = numObservations;

        // Get earliest observation in window
        uint256 earliestPrice = observations[nextObsIndex];

        uint256 currentPrice = getCurrentPrice();

        // Calculate new cumulative observation total
        cumulativeObs = cumulativeObs + currentPrice - earliestPrice;

        // Push new observation into storage and store timestamp taken at
        observations[nextObsIndex] = currentPrice;
        lastObservationTime = uint48(block.timestamp);
        nextObsIndex = (nextObsIndex + 1) % numObs;

        emit NewObservation(block.timestamp, currentPrice, getMovingAverage());
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current price of OHM in the Reserve asset from the price feeds
    function getCurrentPrice() public view returns (uint256) {
        if (!initialized) revert Price_NotInitialized();

        // Get prices from feeds
        uint256 ohmEthPrice;
        uint256 reserveEthPrice;
        {
            (
                uint80 roundId,
                int256 ohmEthPriceInt,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = ohmEthPriceFeed.latestRoundData();

            // Validate chainlink price feed data
            // 1. Answer should be greater than zero
            // 2. Updated at timestamp should be within the update threshold
            // 3. Answered in round ID should be the same as the round ID
            if (
                ohmEthPriceInt <= 0 ||
                updatedAt < block.timestamp - uint256(ohmEthUpdateThreshold) ||
                answeredInRound < roundId
            ) revert Price_BadFeed(address(ohmEthPriceFeed));
            ohmEthPrice = uint256(ohmEthPriceInt);

            int256 reserveEthPriceInt;
            (roundId, reserveEthPriceInt, , updatedAt, answeredInRound) = reserveEthPriceFeed
                .latestRoundData();
            if (
                reserveEthPriceInt <= 0 ||
                updatedAt < block.timestamp - uint256(reserveEthUpdateThreshold) ||
                answeredInRound < roundId
            ) revert Price_BadFeed(address(reserveEthPriceFeed));
            reserveEthPrice = uint256(reserveEthPriceInt);
        }

        // Convert to OHM/RESERVE price
        uint256 currentPrice = (ohmEthPrice * _scaleFactor) / reserveEthPrice;

        return currentPrice;
    }

    /// @notice Get the last stored price observation of OHM in the Reserve asset
    function getLastPrice() external view returns (uint256) {
        if (!initialized) revert Price_NotInitialized();
        uint32 lastIndex = nextObsIndex == 0 ? numObservations - 1 : nextObsIndex - 1;
        return observations[lastIndex];
    }

    /// @notice Get the moving average of OHM in the Reserve asset over the defined window (see movingAverageDuration and observationFrequency).
    function getMovingAverage() public view returns (uint256) {
        if (!initialized) revert Price_NotInitialized();
        return cumulativeObs / numObservations;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the price module
    /// @notice Access restricted to activated policies
    /// @param  startObservations_ - Array of observations to initialize the moving average with. Must be of length numObservations.
    /// @param  lastObservationTime_ - Unix timestamp of last observation being provided (in seconds).
    /// @dev    This function must be called after the Price module is deployed to activate it and after updating the observationFrequency
    ///         or movingAverageDuration (in certain cases) in order for the Price module to function properly.
    function initialize(uint256[] memory startObservations_, uint48 lastObservationTime_)
        external
        permissioned
    {
        if (initialized) revert Price_AlreadyInitialized();

        // Cache numObservations to save gas.
        uint256 numObs = observations.length;

        // Check that the number of start observations matches the number expected
        if (startObservations_.length != numObs || lastObservationTime_ > uint48(block.timestamp))
            revert Price_InvalidParams();

        // Push start observations into storage and total up observations
        uint256 total;
        for (uint256 i; i < numObs; ) {
            if (startObservations_[i] == 0) revert Price_InvalidParams();
            total += startObservations_[i];
            observations[i] = startObservations_[i];
            unchecked {
                ++i;
            }
        }

        // Set cumulative observations, last observation time, and initialized flag
        cumulativeObs = total;
        lastObservationTime = lastObservationTime_;
        initialized = true;
    }

    /// @notice Change the moving average window (duration)
    /// @param  movingAverageDuration_ - Moving average duration in seconds, must be a multiple of observation frequency
    /// @dev    Changing the moving average duration will erase the current observations array
    ///         and require the initialize function to be called again. Ensure that you have saved
    ///         the existing data and can re-populate before calling this function.
    function changeMovingAverageDuration(uint48 movingAverageDuration_) external permissioned {
        // Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (movingAverageDuration_ == 0 || movingAverageDuration_ % observationFrequency != 0)
            revert Price_InvalidParams();

        // Calculate the new number of observations
        uint256 newObservations = uint256(movingAverageDuration_ / observationFrequency);

        // Store blank observations array of new size
        observations = new uint256[](newObservations);

        // Set initialized to false and update state variables
        initialized = false;
        lastObservationTime = 0;
        cumulativeObs = 0;
        nextObsIndex = 0;
        movingAverageDuration = movingAverageDuration_;
        numObservations = uint32(newObservations);

        emit MovingAverageDurationChanged(movingAverageDuration_);
    }

    /// @notice   Change the observation frequency of the moving average (i.e. how often a new observation is taken)
    /// @param    observationFrequency_ - Observation frequency in seconds, must be a divisor of the moving average duration
    /// @dev      Changing the observation frequency clears existing observation data since it will not be taken at the right time intervals.
    ///           Ensure that you have saved the existing data and/or can re-populate before calling this function.
    function changeObservationFrequency(uint48 observationFrequency_) external permissioned {
        // Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (observationFrequency_ == 0 || movingAverageDuration % observationFrequency_ != 0)
            revert Price_InvalidParams();

        // Calculate the new number of observations
        uint256 newObservations = uint256(movingAverageDuration / observationFrequency_);

        // Since the old observations will not be taken at the right intervals,
        // the observations array will need to be reinitialized.
        // Although, there are a handful of situations that could be handled
        // (e.g. clean multiples of the old frequency),
        // it is easier to do so off-chain and reinitialize the array.

        // Store blank observations array of new size
        observations = new uint256[](newObservations);

        // Set initialized to false and update state variables
        initialized = false;
        lastObservationTime = 0;
        cumulativeObs = 0;
        nextObsIndex = 0;
        observationFrequency = observationFrequency_;
        numObservations = uint32(newObservations);

        emit ObservationFrequencyChanged(observationFrequency_);
    }
}

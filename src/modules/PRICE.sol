// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {AggregatorV2V3Interface} from "interfaces/AggregatorV2V3Interface.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Kernel, Module} from "src/Kernel.sol";

import {FullMath} from "libraries/FullMath.sol";

/* ========== ERRORS =========== */
error Price_InvalidParams();
error Price_NotInitialized();
error Price_AlreadyInitialized();
error Price_BadFeed(address priceFeed);

/// @title  Olympus Price Oracle
/// @notice Olympus Price Oracle (Module) Contract
/// @dev    The Olympus Price Oracle contract provides a standard interface for OHM price data against a reserve asset.
///         It also implements a moving average price calculation (same as a TWAP) on the price feed data over a configured
///         duration and observation frequency. The data provided by this contract is used by the Olympus Range Operator to
///         perform market operations. The Olympus Price Oracle is updated each epoch by the Olympus Heart contract.
contract OlympusPrice is Module {
    using FullMath for uint256;

    /* ========== EVENTS =========== */
    event NewObservation(uint256 timestamp, uint256 price);

    /* ========== STATE VARIABLES ========== */

    Kernel.Role public constant KEEPER = Kernel.Role.wrap("PRICE_Keeper");
    Kernel.Role public constant GUARDIAN = Kernel.Role.wrap("PRICE_Guardian");

    /// Chainlink Price Feeds
    /// @dev Chainlink typically provides price feeds for an asset in ETH. Therefore, we use two price feeds against ETH, one for OHM and one for the Reserve asset, to calculate the relative price of OHM in the Reserve asset.
    AggregatorV2V3Interface internal immutable _ohmEthPriceFeed;
    AggregatorV2V3Interface internal immutable _reserveEthPriceFeed;

    /// Moving average data
    uint256 internal _movingAverage; /// See getMovingAverage()

    /// @notice Array of price observations ordered by when they were observed.
    /// @dev    Observations are continually stored and the moving average is over the last movingAverageDuration / observationFrequency observations.
    ///         This allows the contract to maintain historical data. Observations can be cleared by changing the movingAverageDuration or observationFrequency.
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
    uint8 internal immutable _ohmEthDecimals;
    uint8 internal immutable _reserveEthDecimals;

    /// @notice Whether the price module is initialized (and therefore active).
    bool public initialized;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        Kernel kernel_,
        AggregatorV2V3Interface ohmEthPriceFeed_,
        AggregatorV2V3Interface reserveEthPriceFeed_,
        uint48 observationFrequency_,
        uint48 movingAverageDuration_
    ) Module(kernel_) {
        /// @dev Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (
            movingAverageDuration_ == 0 ||
            movingAverageDuration_ % observationFrequency_ != 0
        ) revert Price_InvalidParams();

        /// Set parameters and calculate number of observations
        _ohmEthPriceFeed = ohmEthPriceFeed_;
        _ohmEthDecimals = _ohmEthPriceFeed.decimals();

        _reserveEthPriceFeed = reserveEthPriceFeed_;
        _reserveEthDecimals = _reserveEthPriceFeed.decimals();

        observationFrequency = observationFrequency_;
        movingAverageDuration = movingAverageDuration_;

        numObservations = uint32(
            movingAverageDuration_ / observationFrequency_
        );

        /// Store blank observations array
        observations = new uint256[](numObservations);
        /// nextObsIndex is initialized to 0
    }

    /* ========== FRAMEWORK CONFIGURATION ========== */
    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("PRICE");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](2);
        roles[0] = KEEPER;
        roles[1] = GUARDIAN;
    }

    /* ========== POLICY FUNCTIONS ========== */
    /// @notice Trigger an update of the moving average
    /// @notice Access restricted to approved policies
    /// @dev This function does not have a time-gating on the observationFrequency on this contract. It is set on the Heart policy contract.
    ///      The Heart beat frequency should be set to the same value as the observationFrequency.
    function updateMovingAverage() external onlyRole(KEEPER) {
        /// Revert if not initialized
        if (!initialized) revert Price_NotInitialized();

        /// Cache numbe of observations to save gas.
        uint32 numObs = numObservations;

        /// Get earliest observation in window
        uint256 earliestPrice = observations[nextObsIndex];

        /// Get current price
        uint256 currentPrice = getCurrentPrice();

        /// Calculate new moving average
        if (currentPrice > earliestPrice) {
            _movingAverage += (currentPrice - earliestPrice) / numObs;
        } else {
            _movingAverage -= (earliestPrice - currentPrice) / numObs;
        }

        /// Push new observation into storage and store timestamp taken at
        observations[nextObsIndex] = currentPrice;
        lastObservationTime = uint48(block.timestamp);
        nextObsIndex = (nextObsIndex + 1) % numObs;

        /// Emit event
        emit NewObservation(block.timestamp, currentPrice);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get the current price of OHM in the Reserve asset from the price feeds
    function getCurrentPrice() public view returns (uint256) {
        /// Revert if not initialized
        if (!initialized) revert Price_NotInitialized();

        /// Get prices from feeds
        uint256 ohmEthPrice;
        uint256 reserveEthPrice;
        {
            (, int256 ohmEthPriceInt, , uint256 updatedAt, ) = _ohmEthPriceFeed
                .latestRoundData();
            /// Use a multiple of observation frequency to determine what is too old to use.
            /// Price feeds will not provide an updated answer if the data doesn't change much.
            /// This would be similar to if the feed just stopped updating; therefore, we need a cutoff.
            if (updatedAt < block.timestamp - 3 * uint256(observationFrequency))
                revert Price_BadFeed(address(_ohmEthPriceFeed));
            ohmEthPrice = uint256(ohmEthPriceInt);

            int256 reserveEthPriceInt;
            (, reserveEthPriceInt, , updatedAt, ) = _reserveEthPriceFeed
                .latestRoundData();
            if (updatedAt < block.timestamp - uint256(observationFrequency))
                revert Price_BadFeed(address(_reserveEthPriceFeed));
            reserveEthPrice = uint256(reserveEthPriceInt);
        }

        /// Convert to OHM/RESERVE price
        uint256 currentPrice = ohmEthPrice.mulDiv(
            10**(decimals + _reserveEthDecimals),
            reserveEthPrice * 10**(_ohmEthDecimals)
        );

        return currentPrice;
    }

    /// @notice Get the last stored price observation of OHM in the Reserve asset
    function getLastPrice() external view returns (uint256) {
        /// Revert if not initialized
        if (!initialized) revert Price_NotInitialized();
        uint32 lastIndex = nextObsIndex == 0
            ? numObservations - 1
            : nextObsIndex - 1;
        return observations[lastIndex];
    }

    /// @notice Get the moving average of OHM in the Reserve asset over the defined window (see movingAverageDuration and observationFrequency).
    function getMovingAverage() external view returns (uint256) {
        /// Revert if not initialized
        if (!initialized) revert Price_NotInitialized();
        return _movingAverage;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice                     Initialize the price module
    /// @notice                     Access restricted to approved policies
    /// @param startObservations_   Array of observations to initialize the moving average with. Must be of length numObservations.
    /// @param lastObservationTime_ Unix timestamp of last observation being provided (in seconds).
    /// @dev This function must be called after the Price module is deployed to activate it and after updating the observationFrequency
    ///      or movingAverageDuration (in certain cases) in order for the Price module to function properly.
    function initialize(
        uint256[] memory startObservations_,
        uint48 lastObservationTime_
    ) external onlyRole(GUARDIAN) {
        /// Revert if already initialized
        if (initialized) revert Price_AlreadyInitialized();

        /// Cache numObservations to save gas.
        uint256 numObs = observations.length;

        /// Check that the number of start observations matches the number expected
        if (
            startObservations_.length != numObs ||
            lastObservationTime_ > uint48(block.timestamp)
        ) revert Price_InvalidParams();

        /// Push start observations into storage and total up observations
        uint256 total;
        for (uint256 i; i < numObs; ) {
            if (startObservations_[i] == 0) revert Price_InvalidParams();
            total += startObservations_[i];
            observations[i] = startObservations_[i];
            unchecked {
                ++i;
            }
        }

        /// Set moving average, last observation time, and initialized flag
        _movingAverage = total / numObs;
        lastObservationTime = lastObservationTime_;
        initialized = true;
    }

    /// @notice                         Change the moving average window (duration)
    /// @param movingAverageDuration_   Moving average duration in seconds, must be a multiple of observation frequency
    /// @dev Changing the moving average duration will erase the current observations array
    ///      and require the initialize function to be called again. Ensure that you have saved
    ///      the existing data and can re-populate before calling this function.
    function changeMovingAverageDuration(uint48 movingAverageDuration_)
        external
        onlyRole(GUARDIAN)
    {
        /// Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (
            movingAverageDuration_ == 0 ||
            movingAverageDuration_ % observationFrequency != 0
        ) revert Price_InvalidParams();

        /// Calculate the new number of observations
        uint256 newObservations = uint256(
            movingAverageDuration_ / observationFrequency
        );

        /// Store blank observations array of new size
        observations = new uint256[](newObservations);

        /// Set initialized to false and update state variables
        initialized = false;
        lastObservationTime = 0;
        _movingAverage = 0;
        nextObsIndex = 0;
        movingAverageDuration = movingAverageDuration_;
        numObservations = uint32(newObservations);
    }

    /// @notice   Change the observation frequency of the moving average (i.e. how often a new observation is taken)
    /// @param    observationFrequency_   Observation frequency in seconds, must be a divisor of the moving average duration
    /// @dev      Changing the observation frequency clears existing observation data since it will not be taken at the right time intervals.
    ///           Ensure that you have saved the existing data and/or can re-populate before calling this function.
    function changeObservationFrequency(uint48 observationFrequency_)
        external
        onlyRole(GUARDIAN)
    {
        /// Moving Average Duration should be divisible by Observation Frequency to get a whole number of observations
        if (
            observationFrequency_ == 0 ||
            movingAverageDuration % observationFrequency_ != 0
        ) revert Price_InvalidParams();

        /// Calculate the new number of observations
        uint256 newObservations = uint256(
            movingAverageDuration / observationFrequency_
        );

        /// Since the old observations will not be taken at the right intervals,
        /// the observations array will need to be reinitialized.
        /// Although, there are a handful of situations that could be handled
        /// (e.g. clean multiples of the old frequency),
        /// it is easier to do so off-chain and reinitialize the array.

        /// Store blank observations array of new size
        observations = new uint256[](newObservations);

        /// Set initialized to false and update state variables
        initialized = false;
        lastObservationTime = 0;
        _movingAverage = 0;
        nextObsIndex = 0;
        observationFrequency = observationFrequency_;
        numObservations = uint32(newObservations);
    }
}

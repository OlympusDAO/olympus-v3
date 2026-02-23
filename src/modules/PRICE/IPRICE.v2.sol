// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.15;

import {SubKeycode} from "src/Submodules.sol";

/// @notice Price oracle interface for PRICEv2
/// @dev    Interface extracted from PRICEv2 abstract contract
interface IPRICEv2 {
    // ========== EVENTS ========== //

    /// @notice             An asset's price is stored
    ///
    /// @param asset_       The address of the asset
    /// @param price_       The price of the asset in the system unit of account
    /// @param timestamp_   The timestamp at which the price was calculated
    event PriceStored(address indexed asset_, uint256 price_, uint48 timestamp_);

    /// @notice             An asset's definition is added
    ///
    /// @param asset_       The address of the asset
    event AssetAdded(address indexed asset_);

    /// @notice             An asset's definition is removed
    ///
    /// @param asset_       The address of the asset
    event AssetRemoved(address indexed asset_);

    /// @notice             The price feeds of an asset are updated
    ///
    /// @param asset_       The address of the asset
    event AssetPriceFeedsUpdated(address indexed asset_);

    /// @notice             The price aggregation strategy of an asset is updated
    ///
    /// @param asset_       The address of the asset
    event AssetPriceStrategyUpdated(address indexed asset_);

    /// @notice             The moving average data of an asset is updated
    ///
    /// @param asset_       The address of the asset
    event AssetMovingAverageUpdated(address indexed asset_);

    // ========== ERRORS ========== //

    /// @notice             Passed observation frequency is invalid
    ///
    /// @param frequency_   The observation frequency that was provided
    error PRICE_ObservationFrequencyInvalid(uint32 frequency_);

    /// @notice         The asset is not approved for use
    ///
    /// @param asset_   The address of the asset
    error PRICE_AssetNotApproved(address asset_);

    /// @notice         The asset is not a contract
    /// @dev            Only contract addresses can be used as assets
    ///
    /// @param asset_   The address of the asset
    error PRICE_AssetNotContract(address asset_);

    /// @notice         The asset is already approved for use
    /// @dev            If trying to amend the configuration, use one of the update functions
    ///
    /// @param asset_   The address of the asset
    error PRICE_AssetAlreadyApproved(address asset_);

    /// @notice         A price feed call failed when initially configuring an asset
    ///
    /// @param asset_   The address of the asset that triggered the submodule call
    error PRICE_PriceFeedCallFailed(address asset_);

    /// @notice         The moving average for an asset was requested when it is not stored
    ///
    /// @param asset_   The address of the asset
    error PRICE_MovingAverageNotStored(address asset_);

    /// @notice                         The moving average for an asset was used, but is stale
    ///
    /// @param asset_                   The address of the asset
    /// @param lastObservationTime_     The timestamp of the last observation
    error PRICE_MovingAverageStale(address asset_, uint48 lastObservationTime_);

    /// @notice         The max age is invalid
    ///
    /// @param maxAge_  The max age that was provided
    error PRICE_ParamsMaxAgeInvalid(uint48 maxAge_);

    /// @notice                     The last observation time is invalid
    /// @dev                        The last observation time must be less than the latest timestamp
    ///
    /// @param asset_               The address of the asset
    /// @param lastObservationTime_ The last observation time that was provided
    /// @param earliestTimestamp_   The earliest permissible timestamp
    /// @param latestTimestamp_     The latest permissible timestamp
    error PRICE_ParamsLastObservationTimeInvalid(
        address asset_,
        uint48 lastObservationTime_,
        uint48 earliestTimestamp_,
        uint48 latestTimestamp_
    );

    /// @notice                         The provided moving average duration is invalid
    /// @dev                            The moving average duration must be a integer multiple
    ///                                 of the `observationFrequency_`
    ///
    /// @param asset_                   The address of the asset
    /// @param movingAverageDuration_   The moving average duration that was provided
    /// @param observationFrequency_    The observation frequency that was provided
    error PRICE_ParamsMovingAverageDurationInvalid(
        address asset_,
        uint32 movingAverageDuration_,
        uint48 observationFrequency_
    );

    /// @notice                     The provided observation value is zero
    /// @dev                        Observation values should not be zero
    ///
    /// @param asset_               The address of the asset
    /// @param observationIndex_    The index of the observation that was invalid
    error PRICE_ParamsObservationZero(address asset_, uint256 observationIndex_);

    /// @notice                         The provided observation count is invalid
    ///
    /// @param asset_                   The address of the asset
    /// @param observationCount_        The number of observations that was provided
    /// @param minimumObservationCount_ The minimum number of observations that is permissible
    /// @param maximumObservationCount_ The maximum number of observations that is permissible
    error PRICE_ParamsInvalidObservationCount(
        address asset_,
        uint256 observationCount_,
        uint256 minimumObservationCount_,
        uint256 maximumObservationCount_
    );

    /// @notice                 The number of provided price feeds is insufficient
    ///
    /// @param asset_           The address of the asset
    /// @param feedCount_       The number of price feeds provided
    /// @param feedCountRequired_    The minimum number of price feeds required
    error PRICE_ParamsPriceFeedInsufficient(
        address asset_,
        uint256 feedCount_,
        uint256 feedCountRequired_
    );

    /// @notice         The asset requires storeMovingAverage to be enabled
    /// @dev            This will usually be triggered if the asset is configured to use a moving average
    ///
    /// @param asset_   The address of the asset
    error PRICE_ParamsStoreMovingAverageRequired(address asset_);

    /// @notice                     A strategy must be defined for the asset
    /// @dev                        This will be triggered if strategy specified is insufficient for
    ///                             the configured price feeds and moving average.
    ///
    /// @param asset_               The address of the asset
    /// @param strategy_            The provided strategy, as an encoded `Component` struct
    /// @param feedCount_           The number of price feeds configured for the asset
    /// @param useMovingAverage_    Whether the moving average should be used as an argument to the strategy
    error PRICE_ParamsStrategyInsufficient(
        address asset_,
        bytes strategy_,
        uint256 feedCount_,
        bool useMovingAverage_
    );

    /// @notice         A strategy was provided for a single price source
    /// @dev            Strategy is unnecessary and will not be used
    ///
    /// @param asset_   The asset being configured
    error PRICE_ParamsStrategyNotSupported(address asset_);

    /// @notice         The variant provided in the parameters is invalid
    /// @dev            See the `Variant` enum for valid variants
    ///
    /// @param variant_ The variant that was provided
    error PRICE_ParamsVariantInvalid(Variant variant_);

    /// @notice         The asset returned a price of zero
    /// @dev            This indicates a problem with the configured price feeds for `asset_`.
    ///                 Consider adding more price feeds or using a different price aggregation strategy.
    ///
    /// @param asset_   The address of the asset
    error PRICE_PriceZero(address asset_);

    /// @notice         Executing the price strategy failed
    /// @dev            This indicates a problem with the configured price feeds or strategy for `asset_`.
    ///
    /// @param asset_   The address of the asset
    /// @param data_    The data returned when calling the strategy
    error PRICE_StrategyFailed(address asset_, bytes data_);

    /// @notice         The specified submodule is not installed
    ///
    /// @param asset_   The address of the asset that triggered the submodule lookup
    /// @param target_  The encoded SubKeycode of the submodule
    error PRICE_SubmoduleNotInstalled(address asset_, bytes target_);

    /// @notice         A duplicate price feed was provided when updating an asset's price feeds
    ///
    /// @param asset_   The asset being updated with duplicate price feeds
    /// @param index_   The index of the price feed that is a duplicate
    error PRICE_DuplicatePriceFeed(address asset_, uint256 index_);

    /// @notice         Thrown when updateAsset is called with all update flags set to false
    ///
    /// @param asset_   The address of the asset
    error PRICE_NoUpdatesRequested(address asset_);

    // ========== STATE ========== //

    /// @notice         Struct to hold the configuration for calling a function on a contract
    /// @dev            Used to configure strategy and fees in the `Asset` struct
    ///
    /// @param target   SubKeycode for the target submodule
    /// @param selector The selector of the contract's function
    /// @param params   The parameters to be passed to the function
    struct Component {
        SubKeycode target;
        bytes4 selector;
        bytes params;
    }

    /// @notice                         Struct to hold the configuration for an asset
    ///
    /// @param approved                 Whether the asset is approved for use in the system
    /// @param storeMovingAverage       Whether the moving average should be stored on heartbeats
    /// @param useMovingAverage         Whether the moving average should be provided as an argument to the strategy
    /// @param movingAverageDuration    The duration of the moving average
    /// @param nextObsIndex             The index of obs at which the next observation will be stored
    /// @param numObservations          The number of observations stored
    /// @param lastObservationTime      The last time the moving average was updated
    /// @param cumulativeObs            The cumulative sum of observations
    /// @param obs                      The array of stored observations
    /// @param strategy                 Aggregates feed data into a single price result
    /// @param feeds                    Price feeds stored in order of priority (primary feed in slot 0)
    struct Asset {
        bool approved;
        bool storeMovingAverage;
        bool useMovingAverage;
        uint32 movingAverageDuration;
        uint16 nextObsIndex;
        uint16 numObservations;
        uint48 lastObservationTime;
        uint256 cumulativeObs;
        uint256[] obs;
        bytes strategy;
        bytes feeds;
    }

    /// @notice                         Parameters for updating an asset configuration
    /// @dev                            Only updates components flagged in the struct
    ///
    /// @param updateFeeds              Whether to update price feeds
    /// @param updateStrategy           Whether to update strategy
    /// @param updateMovingAverage      Whether to update moving average configuration
    /// @param feeds                    New price feeds (only read if updateFeeds=true)
    /// @param strategy                 New strategy (only read if updateStrategy=true)
    /// @param useMovingAverage         New useMovingAverage flag (only read if updateStrategy=true)
    /// @param storeMovingAverage       New storeMovingAverage flag (only read if updateMovingAverage=true)
    /// @param movingAverageDuration    New MA duration (only read if updateMovingAverage=true)
    /// @param lastObservationTime      New last observation time (only read if updateMovingAverage=true)
    /// @param observations             New observations (only read if updateMovingAverage=true)
    struct UpdateAssetParams {
        bool updateFeeds;
        bool updateStrategy;
        bool updateMovingAverage;
        Component[] feeds;
        Component strategy;
        bool useMovingAverage;
        bool storeMovingAverage;
        uint32 movingAverageDuration;
        uint48 lastObservationTime;
        uint256[] observations;
    }

    /// @notice         Variant of price to retrieve
    enum Variant {
        CURRENT,
        LAST,
        MOVINGAVERAGE
    }

    /// @notice     The frequency of price observations (in seconds)
    function observationFrequency() external view returns (uint48);

    /// @notice     The number of decimals to used in output values
    function decimals() external view returns (uint8);

    // ========== ASSET INFORMATION ========== //

    /// @notice         Provides a list of registered assets
    ///
    /// @return         The addresses of registered assets
    function getAssets() external view returns (address[] memory);

    /// @notice         Provides the configuration of a specific asset
    ///
    /// @param asset_   The address of the asset
    /// @return         The asset configuration as an `Asset` struct
    function getAssetData(address asset_) external view returns (Asset memory);

    /// @notice         Indicates whether `asset_` has been registered
    ///
    /// @param asset_   The address of the asset
    /// @return         Whether the asset is approved
    function isAssetApproved(address asset_) external view returns (bool);

    // ========== ASSET PRICES ========== //

    /// @notice         Returns the current price of an asset in the system unit of account
    ///
    /// @param asset_   The address of the asset
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_) external view returns (uint256);

    /// @notice         Returns a price no older than the provided age in the system unit of account
    ///
    /// @param asset_   The address of the asset
    /// @param maxAge_  The maximum age (seconds) of the price
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_, uint48 maxAge_) external view returns (uint256);

    /// @notice         Returns the requested variant of the asset price in the system unit of account and the timestamp at which it was calculated
    ///
    /// @param asset_   The address of the asset
    /// @param variant_ The variant of the price to return
    /// @return _price      The USD price of the asset in the scale of `decimals`
    /// @return _timestamp  The timestamp at which the price was calculated
    function getPrice(
        address asset_,
        Variant variant_
    ) external view returns (uint256 _price, uint48 _timestamp);

    /// @notice         Returns the current price of an asset in terms of the base asset
    ///
    /// @param asset_   The address of the asset
    /// @param base_    The address of the base asset that the price will be calculated in
    /// @return         The price of the asset in units of `base_`
    function getPriceIn(address asset_, address base_) external view returns (uint256);

    /// @notice             Returns the price of the asset in terms of the base asset, no older than the max age
    ///
    /// @param asset_       The address of the asset
    /// @param base_        The address of the base asset that the price will be calculated in
    /// @param maxAge_      The maximum age (seconds) of the price
    /// @return             The price of the asset in units of `base_`
    function getPriceIn(
        address asset_,
        address base_,
        uint48 maxAge_
    ) external view returns (uint256);

    /// @notice             Returns the requested variant of the asset price in terms of the base asset
    ///
    /// @param asset_       The address of the asset
    /// @param base_        The address of the base asset that the price will be calculated in
    /// @param variant_     The variant of the price to return
    /// @return _price      The price of the asset in units of `base_`
    /// @return _timestamp  The timestamp at which the price was calculated
    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) external view returns (uint256 _price, uint48 _timestamp);

    /// @notice         Calculates and stores the current price of an asset
    ///
    /// @param asset_   The address of the asset
    function storePrice(address asset_) external;

    /// @notice         Calculates and stores the current price of assets that track a moving average
    function storeObservations() external;

    // ========== ASSET MANAGEMENT ========== //

    /// @notice                         Adds a new asset definition
    ///
    /// @param asset_                   The address of the asset
    /// @param storeMovingAverage_      Whether the moving average should be stored periodically
    /// @param useMovingAverage_        Whether the moving average should be used as an argument to the strategy
    /// @param movingAverageDuration_   The duration of the moving average in seconds
    /// @param lastObservationTime_     The timestamp of the last observation
    /// @param observations_            The observations to be used to initialize the moving average
    /// @param strategy_                The strategy to be used to aggregate price feeds
    /// @param feeds_                   The price feeds to be used to calculate the price
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        Component memory strategy_,
        Component[] memory feeds_
    ) external;

    /// @notice         Removes an asset definition
    ///
    /// @param asset_   The address of the asset
    function removeAsset(address asset_) external;

    /// @notice         Updates an asset configuration atomically
    /// @dev            Only updates components flagged in params_
    /// @dev            Validates entire configuration atomically after updates
    /// @dev            Will revert if:
    /// @dev            - `asset_` is not approved
    /// @dev            - The caller is not permissioned
    /// @dev            - Any updated submodule is not installed
    /// @dev            - The final configuration is invalid
    /// @dev            - All update flags are false (no-op)
    ///
    /// @param asset_   The address of the asset to update
    /// @param params_  Update parameters with flags
    function updateAsset(address asset_, UpdateAssetParams memory params_) external;
}

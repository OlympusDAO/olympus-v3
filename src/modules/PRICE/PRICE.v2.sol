/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Submodules.sol";

/// @notice     Abstract Bophades module for price resolution
/// @author     Oighty
abstract contract PRICEv2 is ModuleWithSubmodules {
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
        uint32 observationFrequency_
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

    // ========== STATE ========== //

    /// @notice         Struct to hold the configuration for calling a function on a contract
    /// @dev            Used to configure strategy and fees in the `Asset` struct
    struct Component {
        SubKeycode target; // submodule keycode
        bytes4 selector; // the function selector of the contract's get() function
        bytes params; // the parameters to be passed to the contract's get() function
    }

    /// @notice         Struct to hold the configuration for an asset
    struct Asset {
        bool approved; // whether the asset is approved for use in the system
        bool storeMovingAverage; // whether the moving average should be stored on heartbeats
        bool useMovingAverage; // whether the moving average should be provided as an argument to the strategy
        uint32 movingAverageDuration; // the duration of the moving average
        uint16 nextObsIndex; // the index of obs at which the next observation will be stored
        uint16 numObservations;
        uint48 lastObservationTime; // the last time the moving average was updated
        uint256 cumulativeObs;
        uint256[] obs;
        bytes strategy; // aggregates feed data into a single price result
        bytes feeds; // price feeds are stored in order of priority, e.g. a primary feed should be stored in the zero slot
    }

    enum Variant {
        CURRENT,
        LAST,
        MOVINGAVERAGE
    }

    // ========== STATIC VARIABLES ========== //

    /// @notice     The frequency of price observations (in seconds)
    uint32 public observationFrequency;

    /// @notice     The number of decimals to used in output values
    uint8 public decimals;

    /// @notice     The addresses of tracked assets
    address[] public assets;

    /// @notice     Maps asset addresses to configuration data
    mapping(address => Asset) internal _assetData;

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @notice         Provides a list of registered assets
    ///
    /// @return         The addresses of registered assets
    function getAssets() external view virtual returns (address[] memory);

    /// @notice         Provides the configuration of a specific asset
    ///
    /// @param asset_   The address of the asset
    /// @return         The asset configuration as an `Asset` struct
    function getAssetData(address asset_) external view virtual returns (Asset memory);

    /// @notice         Indicates whether `asset_` has been registered
    function isAssetApproved(address asset_) external view virtual returns (bool);

    // ========== ASSET PRICES ========== //

    /// @notice         Returns the current price of an asset in the system unit of account
    ///
    /// @param asset_   The address of the asset
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_) external view virtual returns (uint256);

    /// @notice         Returns a price no older than the provided age in the system unit of account
    ///
    /// @param asset_   The address of the asset
    /// @param maxAge_  The maximum age (seconds) of the price
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_, uint48 maxAge_) external view virtual returns (uint256);

    /// @notice         Returns the requested variant of the asset price in the system unit of account and the timestamp at which it was calculated
    ///
    /// @param asset_   The address of the asset
    /// @param variant_ The variant of the price to return
    /// @return _price      The USD price of the asset in the scale of `decimals`
    /// @return _timestamp  The timestamp at which the price was calculated
    function getPrice(
        address asset_,
        Variant variant_
    ) public view virtual returns (uint256 _price, uint48 _timestamp);

    /// @notice         Returns the current price of an asset in terms of the base asset
    ///
    /// @param asset_   The address of the asset
    /// @param base_    The address of the base asset that the price will be calculated in
    /// @return         The price of the asset in units of `base_`
    function getPriceIn(address asset_, address base_) external view virtual returns (uint256);

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
    ) external view virtual returns (uint256);

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
    ) external view virtual returns (uint256 _price, uint48 _timestamp);

    /// @notice         Calculates and stores the current price of an asset
    ///
    /// @param asset_   The address of the asset
    function storePrice(address asset_) external virtual;

    /// @notice         Calculates and stores the current price of assets that track a moving average
    function storeObservations() external virtual;

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
    ) external virtual;

    /// @notice         Removes an asset definition
    ///
    /// @param asset_   The address of the asset
    function removeAsset(address asset_) external virtual;

    /// @notice             Updates the price feeds for an asset
    ///
    /// @param asset_       The address of the asset
    /// @param feeds_       The new price feeds to be used to calculate the price
    function updateAssetPriceFeeds(address asset_, Component[] memory feeds_) external virtual;

    /// @notice                     Updates the price aggregation strategy for an asset
    ///
    /// @param asset_               The address of the asset
    /// @param strategy_            The new strategy to be used to aggregate price feeds
    /// @param useMovingAverage_    Whether the moving average should be used as an argument to the strategy
    function updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) external virtual;

    /// @notice                         Updates the moving average configuration for an asset
    ///
    /// @param asset_                   The address of the asset
    /// @param storeMovingAverage_      Whether the moving average should be stored periodically
    /// @param movingAverageDuration_   The duration of the moving average in seconds
    /// @param lastObservationTime_     The timestamp of the last observation
    /// @param observations_            The observations to be used to initialize the moving average
    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external virtual;
}

abstract contract PriceSubmodule is Submodule {
    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    /// @notice The parent PRICE module
    function _PRICE() internal view returns (PRICEv2) {
        return PRICEv2(address(parent));
    }
}

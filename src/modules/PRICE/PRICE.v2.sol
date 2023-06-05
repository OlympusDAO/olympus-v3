/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Submodules.sol";

abstract contract PRICEv2 is ModuleWithSubmodules {
    // ========== EVENTS ========== //

    event PriceStored(address indexed asset_, uint256 price_, uint48 timestamp_);

    // ========== ERRORS ========== //

    /// @notice         The asset is not approved for use
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
    /// @param asset_   The address of the asset
    /// @param data_    The data returned when calling the strategy
    error PRICE_StrategyFailed(address asset_, bytes data_);

    /// @notice         The specified submodule is not installed
    /// @param asset_   The address of the asset that triggered the submodule lookup
    /// @param target_  The encoded SubKeycode of the submodule
    error PRICE_SubmoduleNotInstalled(address asset_, bytes target_);

    /// @notice         The parameters provided are invalid
    /// @param index    The index of the parameter that is invalid
    /// @param params   The parameters that were provided
    error PRICE_InvalidParams(uint256 index, bytes params); // TODO add asset

    /// @notice         The moving average for an asset was requested when it is not stored
    /// @param asset_   The address of the asset
    error PRICE_MovingAverageNotStored(address asset_);

    // ========== STATE ========== //

    struct Component {
        SubKeycode target; // submodule keycode
        bytes4 selector; // the function selector of the contract's get() function
        bytes params; // the parameters to be passed to the contract's get() function
    }

    struct Asset {
        bool approved; // whether the asset is approved for use in the system
        bool storeMovingAverage; // whether the moving average should be stored on heartbeats, TODO: create a way to store this data and get a list of assets that need to be stored
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

    uint32 public observationFrequency;
    uint8 public decimals;
    address[] public assets;
    mapping(address => Asset) internal _assetData;

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    /// @notice         Provides a list of registered assets
    /// @return         The addresses of registered assets
    function getAssets() external view virtual returns (address[] memory);

    /// @notice         Provides the configuration of a specific asset
    /// @param asset_   The address of the asset
    /// @return         The asset configuration as an `Asset` struct
    function getAssetData(address asset_) external view virtual returns (Asset memory);

    // ========== ASSET PRICES ========== //

    /// @notice         Returns the current price of an asset in the system unit of account
    /// @dev            Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    /// @param asset_   The address of the asset
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_) external view virtual returns (uint256);

    /// @notice         Returns a price no older than the provided age in the system unit of account
    /// @param asset_   The address of the asset
    /// @param maxAge_  The maximum age (seconds) of the price
    /// @return         The USD price of the asset in the scale of `decimals`
    function getPrice(address asset_, uint48 maxAge_) external view virtual returns (uint256);

    /// @notice         Returns the requested variant of the asset price in the system unit of account and the timestamp at which it was calculated
    /// @param asset_   The address of the asset
    /// @param variant_ The variant of the price to return
    /// @return _price      The USD price of the asset in the scale of `decimals`
    /// @return _timestamp  The timestamp at which the price was calculated
    function getPrice(
        address asset_,
        Variant variant_
    ) public view virtual returns (uint256 _price, uint48 _timestamp);

    /// @notice         Returns the current price of an asset in terms of the base asset
    /// @dev            Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    /// @param asset_   The address of the asset
    /// @param base_    The address of the base asset that the price will be calculated in
    /// @return         The price of the asset in units of `base_`
    function getPriceIn(address asset_, address base_) external view virtual returns (uint256);

    /// @notice             Returns the price of the asset in terms of the base asset, no older than the max age
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
    /// @dev            Emits the PriceStored event
    /// @param asset_   The address of the asset
    function storePrice(address asset_) external virtual;

    // ========== ASSET MANAGEMENT ========== //

    /// @notice                         Adds a new asset definition
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
    /// @param asset_   The address of the asset
    function removeAsset(address asset_) external virtual;

    /// @notice             Updates the price feeds for an asset
    /// @param asset_       The address of the asset
    /// @param feeds_       The new price feeds to be used to calculate the price
    function updateAssetPriceFeeds(address asset_, Component[] memory feeds_) external virtual;

    /// @notice                     Updates the price aggregation strategy for an asset
    /// @param asset_               The address of the asset
    /// @param strategy_            The new strategy to be used to aggregate price feeds
    /// @param useMovingAverage_    Whether the moving average should be used as an argument to the strategy
    function updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) external virtual;

    /// @notice                         Updates the moving average configuration for an asset
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
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("PRICE");
    }

    function _PRICE() internal view returns (PRICEv2) {
        return PRICEv2(address(parent));
    }
}

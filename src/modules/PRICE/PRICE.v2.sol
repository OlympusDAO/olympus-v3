/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Submodules.sol";

abstract contract PRICEv2 is ModuleWithSubmodules {
    // ========== EVENTS ========== //
    event PriceStored(address asset_, uint256 price_, uint48 timestamp_);

    // ========== ERRORS ========== //
    error PRICE_AssetNotApproved(address asset_);
    error PRICE_AssetNotContract(address asset_);
    error PRICE_SubmoduleNotInstalled();
    error PRICE_AssetAlreadyApproved(address asset_);
    error PRICE_PriceZero(address asset_);
    error PRICE_PriceCallFailed(address asset_);
    error PRICE_InvalidParams(uint256 index, bytes params);
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
        uint16 nextObsIndex;
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

    uint32 public observationFrequency; // TODO should we be able to specify the observation frequency per Asset?
    uint8 public decimals;
    address[] public assets;
    mapping(address => Asset) internal _assetData;

    ////////////////////////////////////////////////////////////////
    //                      DATA FUNCTIONS                        //
    ////////////////////////////////////////////////////////////////

    // ========== ASSET INFORMATION ========== //

    function getAssets() external view virtual returns (address[] memory);

    function getAssetData(address asset_) external view virtual returns (Asset memory);

    // ========== ASSET PRICES ========== //

    /// @notice Returns the current price of an asset in the system unit of account
    /// @dev Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    function getPrice(address asset_) external view virtual returns (uint256);

    /// @notice Returns a price no older than the provided age in the system unit of account
    function getPrice(address asset_, uint48 maxAge_) external view virtual returns (uint256);

    /// @notice Returns the requested variant of the asset price in the system unit of account and the timestamp at which it was calculated
    function getPrice(
        address asset_,
        Variant variant_
    ) public view virtual returns (uint256, uint48);

    /// @notice Returns the current price of an asset in units of the base asset
    /// @dev Optimistically uses the cached price if it has been updated this block, otherwise calculates price dynamically
    function getPriceIn(address asset_, address base_) external view virtual returns (uint256);

    /// @notice Returns the price of the asset no older than the provided age in units of the base asset
    function getPriceIn(
        address asset_,
        address base_,
        uint48 maxAge_
    ) external view virtual returns (uint256);

    /// @notice Returns the requested variant of the asset price in units of the base asset and the timestamp at which it was calculated
    function getPriceIn(
        address asset_,
        address base_,
        Variant variant_
    ) external view virtual returns (uint256, uint48);

    /// @notice Calculates and stores the current price of an asset
    function storePrice(address asset_) external virtual;

    // ========== ASSET MANAGEMENT ========== //
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

    function removeAsset(address asset_) external virtual;

    function updateAssetPriceFeeds(address asset_, Component[] memory feeds_) external virtual;

    function updateAssetPriceStrategy(
        address asset_,
        Component memory strategy_,
        bool useMovingAverage_
    ) external virtual;

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

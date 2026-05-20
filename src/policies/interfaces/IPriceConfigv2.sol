// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

/// @notice     Interface for PriceConfigv2 policy
/// @dev        Policy to configure PRICEv2
interface IPriceConfigv2 {
    // ========== ERRORS ========== //

    /// @notice Thrown when module does not support interface
    ///
    /// @param  keycode     The keycode of the module
    /// @param  interfaceId The interface identifier, as specified in ERC-165
    error IPriceConfigv2_UnsupportedModuleInterface(bytes5 keycode, bytes4 interfaceId);

    /// @notice Thrown when module version is not supported
    ///
    /// @param  keycode The keycode of the module
    /// @param  major   The major version of the module
    /// @param  minor   The minor version of the module
    error IPriceConfigv2_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

    /// @notice Thrown when the number of feed expectations does not match the number of feeds
    ///
    /// @param  asset_            The address of the asset being configured
    /// @param  expectationCount_ The number of expectations provided
    /// @param  feedCount_        The number of feeds expected
    error IPriceConfigv2_FeedExpectationCountInvalid(
        address asset_,
        uint256 expectationCount_,
        uint256 feedCount_
    );

    /// @notice Thrown when a feed expectation is invalid
    ///
    /// @param  asset_ The address of the asset being configured
    /// @param  index_ The index of the invalid expectation
    error IPriceConfigv2_FeedExpectationInvalid(address asset_, uint256 index_);

    /// @notice Thrown when a feed cannot be queried for expectation validation
    ///
    /// @param  asset_ The address of the asset being configured
    /// @param  index_ The index of the feed that failed
    error IPriceConfigv2_PriceFeedCallFailed(address asset_, uint256 index_);

    /// @notice Thrown when a feed price is outside the configured expectation range
    ///
    /// @param  asset_      The address of the asset being configured
    /// @param  index_      The index of the feed that returned an out-of-bounds price
    /// @param  price_      The price returned by the feed
    /// @param  lowerBound_ The minimum accepted price
    /// @param  upperBound_ The maximum accepted price
    error IPriceConfigv2_PriceFeedOutOfBounds(
        address asset_,
        uint256 index_,
        uint256 price_,
        uint256 lowerBound_,
        uint256 upperBound_
    );

    /// @notice Thrown when a queued submodule action targets a submodule implementation that has changed since queueing
    ///
    /// @param subKeycode The bytes20 keycode of the queued submodule action
    /// @param expected   The submodule implementation installed when the action was queued
    /// @param actual     The submodule implementation installed when the action was executed
    error IPriceConfigv2_SubmoduleImplementationChanged(
        bytes20 subKeycode,
        address expected,
        address actual
    );

    // ========== DATA STRUCTURES ========== //

    /// @notice                     Expected price and tolerance for a configured feed
    /// @dev                        Used as a configuration-time plausibility check only. This
    ///                             does not prove feed identity; a different asset with a similar
    ///                             price can still pass within tolerance.
    ///
    /// @param expectedPrice        Expected feed price in PRICE output decimals
    /// @param toleranceBps         Allowed deviation from expected price, in basis points
    struct PriceFeedExpectation {
        uint256 expectedPrice;
        uint16 toleranceBps;
    }

    // ========================= //
    // TIMELOCK MANAGEMENT       //
    // ========================= //

    /// @notice Queue a timelocked change to the timelock delay
    /// @dev    The delay update is not applied until the queued action is executed. Intended to be callable only by `admin`.
    ///
    /// @param  delay_    The new timelock delay in seconds
    /// @return actionId_ The queued action ID
    function queueTimelockDelay(uint48 delay_) external returns (uint64 actionId_);

    // ========================= //
    // PRICE MANAGEMENT          //
    // ========================= //

    /// @notice Configure a new asset on the PRICE module
    /// @dev    See PRICEv2 for more details on caching behavior when no moving average is stored and component interface
    ///
    /// @param  asset_                  The address of the asset to add
    /// @param  storeMovingAverage_     Whether to store the moving average for this asset
    /// @param  useMovingAverage_       Whether to use the moving average as part of the price resolution strategy for this asset
    /// @param  movingAverageDuration_  The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
    /// @param  lastObservationTime_    The timestamp of the last observation
    /// @param  observations_           The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
    /// @param  strategy_               The price resolution strategy to use for this asset
    /// @param  feeds_                  The array of price feeds to use for this asset
    /// @param  feedExpectations_       Expected price and tolerance for each feed, aligned by index with `feeds_`
    function addAsset(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external;

    /// @notice Register a non-contract asset for management by the PRICE module
    /// @dev    After registration, the address can be used as a non-contract asset identifier in PRICE
    ///
    /// @param  asset_  The non-contract asset address to register
    function registerNonContractAsset(address asset_) external;

    /// @notice Deregister a non-contract asset from management by the PRICE module
    /// @dev    This reverts if the asset is reserved or still configured on PRICE
    ///
    /// @param  asset_  The non-contract asset address to deregister
    function unregisterNonContractAsset(address asset_) external;

    /// @notice Queue removal of an asset from the PRICE module
    /// @dev    After execution, calls to PRICEv2 for the asset's price will revert.
    ///
    /// @param  asset_    The address of the asset to remove
    /// @return actionId_ The queued action ID
    function queueRemoveAsset(address asset_) external returns (uint64 actionId_);

    /// @notice Queue an atomic asset configuration update
    /// @dev    Only updates components flagged in params_ after the queued action is executed.
    /// @dev    See PRICEv2 for more details on the UpdateAssetParams struct
    ///
    /// @param  asset_            The address of the asset to update
    /// @param  params_           Update parameters with flags indicating which components to update
    /// @param  feedExpectations_ Expected price and tolerance for each feed when `params_.updateFeeds` is true. Must be empty otherwise.
    /// @return actionId_         The queued action ID
    function queueUpdateAsset(
        address asset_,
        IPRICEv2.UpdateAssetParams memory params_,
        PriceFeedExpectation[] memory feedExpectations_
    ) external returns (uint64 actionId_);

    /// @notice Store a price observation for an asset
    /// @dev    Calls PRICE.storeObservation(asset_) to calculate and store current price
    ///
    /// @param  asset_  The address of asset
    function storeObservation(address asset_) external;

    /// @notice Store the current price of all assets that track a moving average
    /// @dev    Calls PRICE.storeObservations() to calculate and store observations
    function storeObservations() external;

    // ========================= //
    // SUBMODULE MANAGEMENT      //
    // ========================= //

    /// @notice Install a new submodule on the designated module
    ///
    /// @param  submodule_  The address of the submodule to install
    function installSubmodule(address submodule_) external;

    /// @notice Queue an upgrade of a submodule on the PRICE module
    /// @dev    The upgraded submodule must have the same keycode as an existing submodule that it is replacing, otherwise use installSubmodule.
    ///
    /// @param  submodule_  The address of the submodule to upgrade to
    /// @return actionId_   The queued action ID
    function queueUpgradeSubmodule(address submodule_) external returns (uint64 actionId_);

    /// @notice Queue an action on a PRICE submodule
    /// @dev    The action is not performed until the queued action is executed. This is timelocked
    ///         because PRICE.execOnSubmodule() can call mutable submodule functions.
    /// @dev    This function reverts if:
    /// @dev    - The submodule is not installed
    ///
    /// @param  subKeycode_ The bytes20 keycode of the submodule to call
    /// @param  data_       The calldata to send to the submodule
    /// @return actionId_   The queued action ID
    function queueExecOnSubmodule(
        bytes20 subKeycode_,
        bytes calldata data_
    ) external returns (uint64 actionId_);
}
/// forge-lint: disable-end(mixed-case-function)

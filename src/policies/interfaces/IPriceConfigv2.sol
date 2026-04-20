// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {SubKeycode} from "src/Submodules.sol";

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
    /// @param  keycode     The keycode of the module
    /// @param  major       The major version of the module
    /// @param  minor       The minor version of the module
    error IPriceConfigv2_UnsupportedModuleVersion(bytes5 keycode, uint8 major, uint8 minor);

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
    function addAssetPrice(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        IPRICEv2.Component memory strategy_,
        IPRICEv2.Component[] memory feeds_
    ) external;

    /// @notice Remove an asset from the PRICE module
    /// @dev    After removal, calls to PRICEv2 for the asset's price will revert
    function removeAssetPrice(address asset_) external;

    /// @notice                     Update an asset configuration atomically
    /// @dev                        Only updates components flagged in params_
    /// @dev                        See PRICEv2 for more details on the UpdateAssetParams struct
    ///
    /// @param  asset_              The address of the asset to update
    /// @param  params_             Update parameters with flags indicating which components to update
    function updateAsset(address asset_, IPRICEv2.UpdateAssetParams memory params_) external;

    /// @notice                     Store a price observation for an asset
    /// @dev                        Calls PRICE.storeObservation(asset_) to calculate and store current price
    ///
    /// @param  asset_              The address of asset
    function storeObservation(address asset_) external;

    /// @notice                     Store the current price of all assets that track a moving average
    /// @dev                        Calls PRICE.storeObservations() to calculate and store observations
    function storeObservations() external;

    // ========================= //
    // PRICE CACHE MANAGEMENT    //
    // ========================= //

    /// @notice                     Cache an asset/quote pair price immediately
    /// @dev                        This bypasses staleness checks and always requests a refresh.
    ///                             Use this when the caller explicitly wants a new cached value now.
    ///
    /// @param  asset_              The address of the asset to cache
    /// @param  quote_              The address of the quote asset to cache against
    function cachePrice(address asset_, address quote_) external;

    /// @notice                     Cache an asset/quote pair price only when stale or never cached
    /// @dev                        This is a policy-level cache helper intended for callers that manage
    ///                             staleness explicitly. Unlike oracle clone cache helpers, max age is
    ///                             provided by the caller and not embedded in immutable oracle params.
    ///
    /// @param  asset_              The address of the asset to potentially cache
    /// @param  quote_              The address of the quote asset to potentially cache against
    /// @param  maxAge_             Maximum accepted cache age in seconds
    ///                             If `maxAge_` is 0, any cache from a prior block is treated as stale.
    function cachePriceIfNecessary(address asset_, address quote_, uint48 maxAge_) external;

    // ========================= //
    // SUBMODULE MANAGEMENT      //
    // ========================= //

    /// @notice Install a new submodule on the designated module
    ///
    /// @param  submodule_  The address of the submodule to install
    function installSubmodule(address submodule_) external;

    /// @notice Upgrade a submodule on the PRICE module
    /// @dev    The upgraded submodule must have the same SubKeycode as an existing submodule that it is replacing, otherwise use installSubmodule
    ///
    /// @param  submodule_  The address of the submodule to upgrade to
    function upgradeSubmodule(address submodule_) external;

    /// @notice Perform an action on a submodule
    /// @dev    This function reverts if:
    /// @dev    - PRICE.execOnSubmodule() reverts
    ///
    /// @param  subKeycode_ The SubKeycode of the submodule to call
    /// @param  data_       The calldata to send to the submodule
    function execOnSubmodule(SubKeycode subKeycode_, bytes calldata data_) external;
}
/// forge-lint: disable-end(mixed-case-function)

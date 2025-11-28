// SPDX-License-Identifier: AGPL-3.0
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.0;

import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {SubKeycode} from "src/Submodules.sol";

/// @notice     Interface for PriceConfigv2 policy
/// @dev        Policy to configure PRICEv2
interface IPriceConfigv2 {
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

    /// @notice Update the price feeds for an asset on the PRICE module
    /// @dev    See PRICEv2 for more details on the Component struct
    ///
    /// @param  asset_  The address of the asset to update
    /// @param  feeds_  The array of price feeds to use for this asset
    function updateAssetPriceFeeds(address asset_, IPRICEv2.Component[] memory feeds_) external;

    /// @notice Update the price resolution strategy for an asset on the PRICE module
    /// @dev    See PRICEv2 for more details on the Component struct
    ///
    /// @param  asset_              The address of the asset to update
    /// @param  strategy_           The price resolution strategy to use for this asset
    /// @param  useMovingAverage_   Whether to use the moving average as part of the price resolution strategy for this asset - moving average must be stored to use
    function updateAssetPriceStrategy(
        address asset_,
        IPRICEv2.Component memory strategy_,
        bool useMovingAverage_
    ) external;

    /// @notice Update the moving average data for an asset on the PRICE module
    /// @dev    See PRICEv2 for more details on the caching behavior when no moving average is stored and component interface
    ///
    /// @param  asset_                  The address of the asset to update
    /// @param  storeMovingAverage_     Whether to store the moving average for this asset - cannot remove moving average if being used by strategy (change strategy first)
    /// @param  movingAverageDuration_  The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
    /// @param  lastObservationTime_    The timestamp of the last observation
    /// @param  observations_           The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external;

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

    // ========================= //
    // VERSION                   //
    // ========================= //

    /// @notice     Returns the current version of the policy
    /// @dev        This is useful for distinguishing between different versions of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor);
}
/// forge-lint: disable-end(mixed-case-function)

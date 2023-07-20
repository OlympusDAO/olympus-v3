// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import "modules/PRICE/PRICE.v2.sol";

contract Bookkeeper is Policy, RolesConsumer {
    // DONE
    // [X] Policy setup
    // [X] Install/upgrade submodules
    // [X] Add asset to PRICEv2
    // [X] Remove asset from PRICEv2
    // [X] Update price feeds for asset on PRICEv2
    // [X] Update price strategy for asset on PRICEv2
    // [X] Update moving average data for asset on PRICEv2

    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    // ========== STATE ========== //
    // Modules
    PRICEv2 public PRICE;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("PRICE");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv2(getModuleAddress(dependencies[1]));
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode PRICE_KEYCODE = toKeycode("PRICE");

        requests = new Permissions[](7);
        requests[0] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        requests[1] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        requests[2] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceFeeds.selector);
        requests[3] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceStrategy.selector);
        requests[4] = Permissions(PRICE_KEYCODE, PRICE.updateAssetMovingAverage.selector);
        requests[5] = Permissions(PRICE_KEYCODE, PRICE.installSubmodule.selector);
        requests[6] = Permissions(PRICE_KEYCODE, PRICE.upgradeSubmodule.selector);
    }

    //==================================================================================================//
    //                                      PRICE MANAGEMENT                                            //
    //==================================================================================================//

    /// @notice Configure a new asset on the PRICE module
    /// @dev see PRICEv2 for more details on caching behavior when no moving average is stored and component interface
    /// @param asset_ The address of the asset to add
    /// @param storeMovingAverage_ Whether to store the moving average for this asset
    /// @param useMovingAverage_ Whether to use the moving average as part of the price resolution strategy for this asset
    /// @param movingAverageDuration_ The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
    /// @param lastObservationTime_ The timestamp of the last observation
    /// @param observations_ The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
    /// @param strategy_ The price resolution strategy to use for this asset
    /// @param feeds_ The array of price feeds to use for this asset
    function addAssetPrice(
        address asset_,
        bool storeMovingAverage_,
        bool useMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_,
        PRICEv2.Component memory strategy_,
        PRICEv2.Component[] memory feeds_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.addAsset(
            asset_,
            storeMovingAverage_,
            useMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_,
            strategy_,
            feeds_
        );
    }

    /// @notice Remove an asset from the PRICE module
    /// @dev After removal, calls to PRICEv2 for the asset's price will revert
    function removeAssetPrice(address asset_) external onlyRole("bookkeeper_policy") {
        PRICE.removeAsset(asset_);
    }

    /// @notice Update the price feeds for an asset on the PRICE module
    /// @dev see PRICEv2 for more details on the Component struct
    /// @param asset_ The address of the asset to update
    /// @param feeds_ The array of price feeds to use for this asset
    function updateAssetPriceFeeds(
        address asset_,
        PRICEv2.Component[] memory feeds_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.updateAssetPriceFeeds(asset_, feeds_);
    }

    /// @notice Update the price resolution strategy for an asset on the PRICE module
    /// @dev see PRICEv2 for more details on the Component struct
    /// @param asset_ The address of the asset to update
    /// @param strategy_ The price resolution strategy to use for this asset
    /// @param useMovingAverage_ Whether to use the moving average as part of the price resolution strategy for this asset - moving average must be stored to use
    function updateAssetPriceStrategy(
        address asset_,
        PRICEv2.Component memory strategy_,
        bool useMovingAverage_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.updateAssetPriceStrategy(asset_, strategy_, useMovingAverage_);
    }

    /// @notice Update the moving average data for an asset on the PRICE module
    /// @dev see PRICEv2 for more details on the caching behavior when no moving average is stored and component interface
    /// @param asset_ The address of the asset to update
    /// @param storeMovingAverage_ Whether to store the moving average for this asset - cannot remove moving average if being used by strategy (change strategy first)
    /// @param movingAverageDuration_ The duration of the moving average in seconds, only used if `storeMovingAverage_` is true
    /// @param lastObservationTime_ The timestamp of the last observation
    /// @param observations_ The array of observations to add - the number of observations must match the moving average duration divided by the PRICEv2 observation frequency
    function updateAssetMovingAverage(
        address asset_,
        bool storeMovingAverage_,
        uint32 movingAverageDuration_,
        uint48 lastObservationTime_,
        uint256[] memory observations_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.updateAssetMovingAverage(
            asset_,
            storeMovingAverage_,
            movingAverageDuration_,
            lastObservationTime_,
            observations_
        );
    }

    //==================================================================================================//
    //                                      SUBMODULE MANAGEMENT                                        //
    //==================================================================================================//

    /// @notice Install a new submodule on the PRICE module, which can be a new strategy or feed
    function installSubmodule(Submodule submodule_) external onlyRole("bookkeeper_admin") {
        PRICE.installSubmodule(submodule_);
    }

    /// @notice Upgrade a submodule on the PRICE module
    /// @dev The upgraded submodule must have the same SubKeycode as an existing submodule that it is replacing,
    /// otherwise use installSubmodule
    function upgradeSubmodule(Submodule submodule_) external onlyRole("bookkeeper_admin") {
        PRICE.upgradeSubmodule(submodule_);
    }
}

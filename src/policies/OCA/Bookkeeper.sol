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
    error Bookkeeper_InvalidModule(Keycode module_);

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

    function removeAssetPrice(address asset_) external onlyRole("bookkeeper_policy") {
        PRICE.removeAsset(asset_);
    }

    function updateAssetPriceFeeds(
        address asset_,
        PRICEv2.Component[] memory feeds_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.updateAssetPriceFeeds(asset_, feeds_);
    }

    function updateAssetPriceStrategy(
        address asset_,
        PRICEv2.Component memory strategy_,
        bool useMovingAverage_
    ) external onlyRole("bookkeeper_policy") {
        PRICE.updateAssetPriceStrategy(asset_, strategy_, useMovingAverage_);
    }

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

    function installSubmodule(
        Keycode moduleKeycode_,
        Submodule submodule_
    ) external onlyRole("bookkeeper_admin") {
        if (fromKeycode(moduleKeycode_) == bytes5("PRICE")) {
            PRICE.installSubmodule(submodule_);
        } else {
            revert Bookkeeper_InvalidModule(moduleKeycode_);
        }
    }

    function upgradeSubmodule(
        Keycode moduleKeycode_,
        Submodule submodule_
    ) external onlyRole("bookkeeper_admin") {
        if (fromKeycode(moduleKeycode_) == bytes5("PRICE")) {
            PRICE.upgradeSubmodule(submodule_);
        } else {
            revert Bookkeeper_InvalidModule(moduleKeycode_);
        }
    }

    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external onlyRole("bookkeeper_policy") {
        bytes20 subKeycode = fromSubKeycode(subKeycode_);
        bytes5 moduleKeycode = bytes5(subKeycode >> (15 * 8));
        if (moduleKeycode == bytes5("PRICE")) {
            PRICE.execOnSubmodule(subKeycode_, data_);
        } else {
            revert Bookkeeper_InvalidModule(toKeycode(moduleKeycode));
        }
    }
}

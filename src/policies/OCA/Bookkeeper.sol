// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import "modules/PRICE/PRICE.v2.sol";
import {SPPLYv1, Category as SupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";
import {TRSRYv1_1, CategoryGroup as AssetCategoryGroup, Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";

contract Bookkeeper is Policy, RolesConsumer {
    // DONE
    // [X] Policy setup
    // [X] Install/upgrade submodules
    // [X] Add asset to PRICEv2
    // [X] Remove asset from PRICEv2
    // [X] Update price feeds for asset on PRICEv2
    // [X] Update price strategy for asset on PRICEv2
    // [X] Update moving average data for asset on PRICEv2
    // [X] Add category to SPPLYv1
    // [X] Remove category from SPPLYv1
    // [X] Categorize address in SPPLYv1
    // [X] Add asset to TRSRYv1.1
    // [X] Add category group to TRSRYv1.1
    // [X] Add category to TRSRYv1.1
    // [X] Add location to asset on TRSRYv1.1
    // [X] Remove location from asset on TRSRYv1.1
    // [X] Categorize asset on TRSRYv1.1

    // ========== ERRORS ========== //
    error Bookkeeper_InvalidModule(Keycode module_);

    // ========== EVENTS ========== //

    // ========== STATE ========== //
    // Modules
    PRICEv2 public PRICE;
    SPPLYv1 public SPPLY;
    TRSRYv1_1 public TRSRY;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("SPPLY");
        dependencies[3] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        PRICE = PRICEv2(getModuleAddress(dependencies[1]));
        SPPLY = SPPLYv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1_1(getModuleAddress(dependencies[3]));

        (uint8 PRICE_MAJOR, ) = PRICE.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 SPPLY_MAJOR, ) = SPPLY.VERSION();
        (uint8 TRSRY_MAJOR, uint8 TRSRY_MINOR) = TRSRY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([2, 1, 1, 1]);
        if (PRICE_MAJOR != 2 || ROLES_MAJOR != 1 || SPPLY_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Check TRSRY minor version
        if (TRSRY_MINOR < 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode PRICE_KEYCODE = toKeycode("PRICE");
        Keycode SPPLY_KEYCODE = toKeycode("SPPLY");
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](18);
        // PRICE Permissions
        requests[0] = Permissions(PRICE_KEYCODE, PRICE.addAsset.selector);
        requests[1] = Permissions(PRICE_KEYCODE, PRICE.removeAsset.selector);
        requests[2] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceFeeds.selector);
        requests[3] = Permissions(PRICE_KEYCODE, PRICE.updateAssetPriceStrategy.selector);
        requests[4] = Permissions(PRICE_KEYCODE, PRICE.updateAssetMovingAverage.selector);
        requests[5] = Permissions(PRICE_KEYCODE, PRICE.installSubmodule.selector);
        requests[6] = Permissions(PRICE_KEYCODE, PRICE.upgradeSubmodule.selector);
        // SPPLY Permissions
        requests[7] = Permissions(SPPLY_KEYCODE, SPPLY.addCategory.selector);
        requests[8] = Permissions(SPPLY_KEYCODE, SPPLY.removeCategory.selector);
        requests[9] = Permissions(SPPLY_KEYCODE, SPPLY.categorize.selector);
        requests[10] = Permissions(SPPLY_KEYCODE, SPPLY.installSubmodule.selector);
        requests[11] = Permissions(SPPLY_KEYCODE, SPPLY.upgradeSubmodule.selector);
        // TRSRY Permissions
        requests[12] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        requests[13] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        requests[14] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        requests[15] = Permissions(TRSRY_KEYCODE, TRSRY.addCategoryGroup.selector);
        requests[16] = Permissions(TRSRY_KEYCODE, TRSRY.addCategory.selector);
        requests[17] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);
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
    //                                      SUPPLY MANAGEMENT                                           //
    //==================================================================================================//

    /// @notice Add a new category to the supply tracking system
    /// @param category_ The category to add
    function addSupplyCategory(
        SupplyCategory category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_,
        bytes4 submoduleReservesSelector_
    ) external onlyRole("bookkeeper_policy") {
        SPPLY.addCategory(
            category_,
            useSubmodules_,
            submoduleSelector_,
            submoduleReservesSelector_
        );
    }

    /// @notice Remove a category from the supply tracking system
    /// @param category_ The category to remove
    function removeSupplyCategory(SupplyCategory category_) external onlyRole("bookkeeper_policy") {
        SPPLY.removeCategory(category_);
    }

    /// @notice Categorize an address in a supply category
    /// @param location_ The address to categorize
    /// @param category_ The category to add the address to
    function categorizeSupply(
        address location_,
        SupplyCategory category_
    ) external onlyRole("bookkeeper_policy") {
        SPPLY.categorize(location_, category_);
    }

    //==================================================================================================//
    //                                      TREASURY MANAGEMENT                                         //
    //==================================================================================================//

    /// @notice Add a new asset to the treasury for tracking
    /// @param asset_ The address of the asset to add
    /// @param locations_ Array of locations other than TRSRY to get balance from
    function addAsset(
        address asset_,
        address[] calldata locations_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.addAsset(asset_, locations_);
    }

    /// @notice Add a new location to a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to add the location to
    /// @param location_ The address of the location to add
    function addAssetLocation(
        address asset_,
        address location_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.addAssetLocation(asset_, location_);
    }

    /// @notice Remove a location from a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to remove the location from
    /// @param location_ The address of the location to remove
    function removeAssetLocation(
        address asset_,
        address location_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.removeAssetLocation(asset_, location_);
    }

    /// @notice Add a new category group to the treasury for tracking
    /// @param categoryGroup_ The category group to add
    function addAssetCategoryGroup(
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.addCategoryGroup(categoryGroup_);
    }

    /// @notice Add a new category to a specific category group on the treasury for tracking
    /// @param category_ The category to add
    /// @param categoryGroup_ The category group to add the category to
    function addAssetCategory(
        AssetCategory category_,
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.addCategory(category_, categoryGroup_);
    }

    /// @notice Categorize a location in a category
    /// @param asset_ The address of the asset to categorize
    /// @param category_ The category to add the asset to
    /// @dev This categorization is done within a category group. So for example if an asset is categorized
    ///      as 'liquid' which is part of the 'liquidity-preference' group, but then is changed to 'illiquid'
    ///      which falls under the same 'liquidity-preference' group, the asset will lose its 'liquid' categorization
    ///      and gain the 'illiquid' categorization (all under the 'liquidity-preference' group).
    function categorizeAsset(
        address asset_,
        AssetCategory category_
    ) external onlyRole("bookkeeper_policy") {
        TRSRY.categorize(asset_, category_);
    }

    //==================================================================================================//
    //                                      SUBMODULE MANAGEMENT                                        //
    //==================================================================================================//

    /// @notice Install a new submodule on the designated module
    function installSubmodule(
        Keycode moduleKeycode_,
        Submodule submodule_
    ) external onlyRole("bookkeeper_admin") {
        if (fromKeycode(moduleKeycode_) == bytes5("PRICE")) {
            PRICE.installSubmodule(submodule_);
        } else if (fromKeycode(moduleKeycode_) == bytes5("SPPLY")) {
            SPPLY.installSubmodule(submodule_);
        } else {
            revert Bookkeeper_InvalidModule(moduleKeycode_);
        }
    }

    /// @notice Upgrade a submodule on the PRICE module
    /// @dev The upgraded submodule must have the same SubKeycode as an existing submodule that it is replacing,
    /// otherwise use installSubmodule
    function upgradeSubmodule(
        Keycode moduleKeycode_,
        Submodule submodule_
    ) external onlyRole("bookkeeper_admin") {
        if (fromKeycode(moduleKeycode_) == bytes5("PRICE")) {
            PRICE.upgradeSubmodule(submodule_);
        } else if (fromKeycode(moduleKeycode_) == bytes5("SPPLY")) {
            SPPLY.upgradeSubmodule(submodule_);
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
        } else if (moduleKeycode == bytes5("SPPLY")) {
            SPPLY.execOnSubmodule(subKeycode_, data_);
        } else {
            revert Bookkeeper_InvalidModule(toKeycode(moduleKeycode));
        }
    }
}

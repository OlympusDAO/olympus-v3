// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import "src/Submodules.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1_1, CategoryGroup as AssetCategoryGroup, Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";

/// @notice Configures asset definitions and categorisations on the TRSRY module
/// @dev    Some functions in this policy are gated to addresses with the "treasuryconfig_policy" role
contract TreasuryConfig is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    // =========  ERRORS ========= //

    // =========  STATE ========= //

    TRSRYv1_1 public TRSRY;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("ROLES");

        TRSRY = TRSRYv1_1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 TRSRY_MAJOR, uint8 TRSRY_MINOR) = TRSRY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (ROLES_MAJOR != 1 || TRSRY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        // Check TRSRY minor version
        if (TRSRY_MINOR < 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        requests = new Permissions[](6);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.addCategoryGroup.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.addCategory.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);
    }

    /// @notice     Returns the current version of the policy
    /// @dev        This is useful for distinguishing between different versions of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 1;
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
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.addAsset(asset_, locations_);
    }

    /// @notice Add a new location to a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to add the location to
    /// @param location_ The address of the location to add
    function addAssetLocation(
        address asset_,
        address location_
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.addAssetLocation(asset_, location_);
    }

    /// @notice Remove a location from a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to remove the location from
    /// @param location_ The address of the location to remove
    function removeAssetLocation(
        address asset_,
        address location_
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.removeAssetLocation(asset_, location_);
    }

    /// @notice Add a new category group to the treasury for tracking
    /// @param categoryGroup_ The category group to add
    function addAssetCategoryGroup(
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.addCategoryGroup(categoryGroup_);
    }

    /// @notice Add a new category to a specific category group on the treasury for tracking
    /// @param category_ The category to add
    /// @param categoryGroup_ The category group to add the category to
    function addAssetCategory(
        AssetCategory category_,
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("treasuryconfig_policy") {
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
    ) external onlyRole("treasuryconfig_policy") {
        TRSRY.categorize(asset_, category_);
    }
}

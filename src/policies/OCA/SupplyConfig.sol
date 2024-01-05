// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

import "src/Submodules.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {SPPLYv1, Category as SupplyCategory} from "modules/SPPLY/SPPLY.v1.sol";

/// @notice Activates and configures the SPPLY module
/// @dev    Some functions in this policy are gated to addresses with the "supplyconfig_policy" or "supplyconfig_admin" roles
contract SupplyConfig is Policy, RolesConsumer {
    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    // ========== STATE ========== //

    // Modules
    SPPLYv1 public SPPLY;

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("SPPLY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        SPPLY = SPPLYv1(getModuleAddress(dependencies[1]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        (uint8 SPPLY_MAJOR, ) = SPPLY.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (ROLES_MAJOR != 1 || SPPLY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode SPPLY_KEYCODE = toKeycode("SPPLY");

        requests = new Permissions[](6);
        // SPPLY Permissions
        requests[0] = Permissions(SPPLY_KEYCODE, SPPLY.addCategory.selector);
        requests[1] = Permissions(SPPLY_KEYCODE, SPPLY.removeCategory.selector);
        requests[2] = Permissions(SPPLY_KEYCODE, SPPLY.categorize.selector);
        requests[3] = Permissions(SPPLY_KEYCODE, SPPLY.installSubmodule.selector);
        requests[4] = Permissions(SPPLY_KEYCODE, SPPLY.upgradeSubmodule.selector);
        requests[5] = Permissions(SPPLY_KEYCODE, SPPLY.execOnSubmodule.selector);
    }

    /// @notice     Returns the current version of the policy
    /// @dev        This is useful for distinguishing between different versions of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //==================================================================================================//
    //                                      SUPPLY MANAGEMENT                                           //
    //==================================================================================================//

    /// @notice             Add a new category to the supply tracking system
    ///
    /// @param category_    The category to add
    function addSupplyCategory(
        SupplyCategory category_,
        bool useSubmodules_,
        bytes4 submoduleSelector_,
        bytes4 submoduleReservesSelector_
    ) external onlyRole("supplyconfig_policy") {
        SPPLY.addCategory(
            category_,
            useSubmodules_,
            submoduleSelector_,
            submoduleReservesSelector_
        );
    }

    /// @notice             Remove a category from the supply tracking system
    ///
    /// @param category_    The category to remove
    function removeSupplyCategory(
        SupplyCategory category_
    ) external onlyRole("supplyconfig_policy") {
        SPPLY.removeCategory(category_);
    }

    /// @notice             Categorize an address in a supply category
    ///
    /// @param location_    The address to categorize
    /// @param category_    The category to add the address to
    function categorizeSupply(
        address location_,
        SupplyCategory category_
    ) external onlyRole("supplyconfig_policy") {
        SPPLY.categorize(location_, category_);
    }

    //==================================================================================================//
    //                                      SUBMODULE MANAGEMENT                                        //
    //==================================================================================================//

    /// @notice Install a new submodule
    function installSubmodule(Submodule submodule_) external onlyRole("supplyconfig_admin") {
        SPPLY.installSubmodule(submodule_);
    }

    /// @notice Upgrade a submodule
    /// @dev    The upgraded submodule must have the same SubKeycode as an existing submodule that it is replacing,
    /// @dev    otherwise use installSubmodule
    function upgradeSubmodule(Submodule submodule_) external onlyRole("supplyconfig_admin") {
        SPPLY.upgradeSubmodule(submodule_);
    }

    /// @notice Perform an action on a submodule
    /// @dev    This function reverts if:
    /// @dev    - SPPLY.execOnSubmodule() reverts
    function execOnSubmodule(
        SubKeycode subKeycode_,
        bytes calldata data_
    ) external onlyRole("supplyconfig_policy") {
        SPPLY.execOnSubmodule(subKeycode_, data_);
    }
}

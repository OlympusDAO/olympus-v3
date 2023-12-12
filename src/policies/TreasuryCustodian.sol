// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {ROLESv1, RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {TRSRYv1_1, CategoryGroup as AssetCategoryGroup, Category as AssetCategory} from "modules/TRSRY/TRSRY.v1.sol";

import "src/Kernel.sol";

/// @notice     Allows authorized callers to interact with the TRSRY module
/// @notice     This can be used to set and remove approvals, allocate assets for yield and define assets, categories and locations
/// @dev        Callers must have the "custodian" role in order to interact with this policy
contract TreasuryCustodian is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    event ApprovalRevoked(address indexed policy_, ERC20[] tokens_);

    // =========  ERRORS ========= //

    error Custodian_PolicyStillActive();

    error TreasuryCustodian_InvalidModule(Keycode module_);

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

        requests = new Permissions[](12);
        requests[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseWithdrawApproval.selector);
        requests[3] = Permissions(TRSRY_KEYCODE, TRSRY.increaseDebtorApproval.selector);
        requests[4] = Permissions(TRSRY_KEYCODE, TRSRY.decreaseDebtorApproval.selector);
        requests[5] = Permissions(TRSRY_KEYCODE, TRSRY.setDebt.selector);
        requests[6] = Permissions(TRSRY_KEYCODE, TRSRY.addAsset.selector);
        requests[7] = Permissions(TRSRY_KEYCODE, TRSRY.addAssetLocation.selector);
        requests[8] = Permissions(TRSRY_KEYCODE, TRSRY.removeAssetLocation.selector);
        requests[9] = Permissions(TRSRY_KEYCODE, TRSRY.addCategoryGroup.selector);
        requests[10] = Permissions(TRSRY_KEYCODE, TRSRY.addCategory.selector);
        requests[11] = Permissions(TRSRY_KEYCODE, TRSRY.categorize.selector);
    }

    /// @notice     Returns the current version of the policy
    /// @dev        This is useful for distinguishing between different versions of the policy
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 1;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    /// @notice Allow an address to withdraw `amount_` from the treasury
    function grantWithdrawerApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.increaseWithdrawApproval(for_, token_, amount_);
    }

    /// @notice Lower an address's withdrawer approval
    function reduceWithdrawerApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.decreaseWithdrawApproval(for_, token_, amount_);
    }

    /// @notice Custodian can withdraw reserves to an address.
    /// @dev    Used for withdrawing assets to a MS or other address in special cases.
    function withdrawReservesTo(
        address to_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.withdrawReserves(to_, token_, amount_);
    }

    /// @notice Allow an address to incur `amount_` of debt from the treasury
    function grantDebtorApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.increaseDebtorApproval(for_, token_, amount_);
    }

    /// @notice Lower an address's debtor approval
    function reduceDebtorApproval(
        address for_,
        ERC20 token_,
        uint256 amount_
    ) external onlyRole("custodian") {
        TRSRY.decreaseDebtorApproval(for_, token_, amount_);
    }

    /// @notice Allow authorized addresses to increase debt in special cases
    function increaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole("custodian") {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(debtor_, token_, debt + amount_);
    }

    /// @notice Allow authorized addresses to decrease debt in special cases
    function decreaseDebt(
        ERC20 token_,
        address debtor_,
        uint256 amount_
    ) external onlyRole("custodian") {
        uint256 debt = TRSRY.reserveDebt(token_, debtor_);
        TRSRY.setDebt(debtor_, token_, debt - amount_);
    }

    /// @notice Anyone can call to revoke a deactivated policy's approvals.
    function revokePolicyApprovals(
        address policy_,
        ERC20[] memory tokens_
    ) external onlyRole("custodian") {
        if (Policy(policy_).isActive()) revert Custodian_PolicyStillActive();

        uint256 len = tokens_.length;
        for (uint256 j; j < len; ) {
            uint256 wApproval = TRSRY.withdrawApproval(policy_, tokens_[j]);
            if (wApproval > 0) TRSRY.decreaseWithdrawApproval(policy_, tokens_[j], wApproval);

            uint256 dApproval = TRSRY.debtApproval(policy_, tokens_[j]);
            if (dApproval > 0) TRSRY.decreaseDebtorApproval(policy_, tokens_[j], dApproval);

            unchecked {
                ++j;
            }
        }

        emit ApprovalRevoked(policy_, tokens_);
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
    ) external onlyRole("custodian") {
        TRSRY.addAsset(asset_, locations_);
    }

    /// @notice Add a new location to a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to add the location to
    /// @param location_ The address of the location to add
    function addAssetLocation(address asset_, address location_) external onlyRole("custodian") {
        TRSRY.addAssetLocation(asset_, location_);
    }

    /// @notice Remove a location from a specific asset on the treasury for tracking
    /// @param asset_ The address of the asset to remove the location from
    /// @param location_ The address of the location to remove
    function removeAssetLocation(address asset_, address location_) external onlyRole("custodian") {
        TRSRY.removeAssetLocation(asset_, location_);
    }

    /// @notice Add a new category group to the treasury for tracking
    /// @param categoryGroup_ The category group to add
    function addAssetCategoryGroup(
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("custodian") {
        TRSRY.addCategoryGroup(categoryGroup_);
    }

    /// @notice Add a new category to a specific category group on the treasury for tracking
    /// @param category_ The category to add
    /// @param categoryGroup_ The category group to add the category to
    function addAssetCategory(
        AssetCategory category_,
        AssetCategoryGroup categoryGroup_
    ) external onlyRole("custodian") {
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
    ) external onlyRole("custodian") {
        TRSRY.categorize(asset_, category_);
    }
}

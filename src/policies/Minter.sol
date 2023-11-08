// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

/// @title Olympus Minter Policy
/// @notice Olympus Minter Policy Contract
/// @dev This policy is to enable minting of OHM by the DAO MS to support test runs of new products which have not been automated yet.
///      This policy will be removed once the protocol completes feature development and the DAO no longer needs to test products.
///      This policy requires categories to be created to designate the purpose for minted OHM, which can be tracked externally from automated systems.
contract Minter is Policy, RolesConsumer {
    // ========== ERRORS ========== //

    error Minter_CategoryNotApproved();
    error Minter_CategoryApproved();

    // ========== EVENTS ========== //

    event Mint(address indexed to, bytes32 indexed category, uint256 amount);
    event CategoryAdded(bytes32 category);
    event CategoryRemoved(bytes32 category);

    // ========== STATE ========== //

    // Modules
    MINTRv1 internal MINTR;

    // Mint metadata
    /// @notice List of approved categories for logging OHM mints
    bytes32[] public categories;
    /// @notice Whether a category is approved for logging
    /// @dev This is used to prevent logging of mint events that are not consistent with standardized names
    mapping(bytes32 => bool) public categoryApproved;

    // ========= POLICY SETUP ========= //

    constructor(Kernel kernel_) Policy(kernel_) {}

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("ROLES");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");

        requests = new Permissions[](2);
        requests[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
    }

    // ========= MINT FUNCTIONS ========= //

    modifier onlyApproved(bytes32 category_) {
        if (!categoryApproved[category_]) revert Minter_CategoryNotApproved();
        _;
    }

    /// @notice Mint OHM to an address
    /// @param to_ Address to mint OHM to
    /// @param amount_ Amount of OHM to mint
    function mint(
        address to_,
        uint256 amount_,
        bytes32 category_
    ) external onlyRole("minter_admin") onlyApproved(category_) {
        // Increase mint allowance by provided amount
        MINTR.increaseMintApproval(address(this), amount_);

        // Mint the OHM
        MINTR.mintOhm(to_, amount_);

        // Emit a mint event
        emit Mint(to_, category_, amount_);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Add a category to the list of approved mint categories
    /// @param category_ Category to add
    function addCategory(bytes32 category_) external onlyRole("minter_admin") {
        if (categoryApproved[category_]) revert Minter_CategoryApproved();
        categories.push(category_);
        categoryApproved[category_] = true;

        emit CategoryAdded(category_);
    }

    /// @notice Remove a category from the list of approved mint categories
    /// @param category_ Category to remove
    function removeCategory(bytes32 category_) external onlyRole("minter_admin") {
        if (!categoryApproved[category_]) revert Minter_CategoryNotApproved();
        uint256 len = categories.length;
        for (uint256 i; i < len; ++i) {
            if (categories[i] == category_) {
                categories[i] = categories[len - 1];
                categories.pop();
                break;
            }
        }
        categoryApproved[category_] = false;

        emit CategoryRemoved(category_);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Get the list of approved mint categories
    function getCategories() external view returns (bytes32[] memory) {
        return categories;
    }
}

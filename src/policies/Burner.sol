// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {TransferHelper} from "libraries/TransferHelper.sol";

import {RolesConsumer} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "modules/TRSRY/TRSRY.v1.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import "src/Kernel.sol";

/// @title Olympus Burner Policy
/// @notice Olympus Burner Policy Contract
/// @dev This policy is to enable burning of OHM by the DAO MS to support test runs of new products which have not been automated yet.
///      This policy will be removed once the protocol completes feature development and the DAO no longer needs to test products.
///      This policy requires categories to be created to designate the purpose for burned OHM, which can be tracked externally from automated systems.
contract Burner is Policy, RolesConsumer {
    using TransferHelper for ERC20;

    // ========== ERRORS ========== //

    error Burner_CategoryNotApproved();
    error Burner_CategoryApproved();

    // ========== EVENTS ========== //

    event Burn(address indexed from, bytes32 indexed category, uint256 amount);
    event CategoryAdded(bytes32 category);
    event CategoryRemoved(bytes32 category);

    // ========== STATE ========== //

    // Modules
    TRSRYv1 internal TRSRY;
    MINTRv1 internal MINTR;

    // Olympus contract dependencies
    /// @notice OHM token
    ERC20 public immutable ohm;

    // Burn metadata
    /// @notice List of approved categories for logging OHM burns
    bytes32[] public categories;
    /// @notice Whether a category is approved for logging
    /// @dev This is used to prevent logging of burn events that are not consistent with standardized names
    mapping(bytes32 => bool) public categoryApproved;

    // ========= POLICY SETUP ========= //

    constructor(Kernel kernel_, ERC20 ohm_) Policy(kernel_) {
        ohm = ohm_;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));

        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1, 1]);
        if (MINTR_MAJOR != 1 || ROLES_MAJOR != 1 || TRSRY_MAJOR != 1)
            revert Policy_WrongModuleVersion(expected);

        // Approve MINTR for burning OHM (called here so that it is re-approved on updates)
        ohm.safeApprove(address(MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode TRSRY_KEYCODE = toKeycode("TRSRY");

        requests = new Permissions[](3);
        requests[0] = Permissions(MINTR.KEYCODE(), MINTR.burnOhm.selector);
        requests[1] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        requests[2] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
    }

    // ========= BURN FUNCTIONS ========= //

    modifier onlyApproved(bytes32 category_) {
        if (!categoryApproved[category_]) revert Burner_CategoryNotApproved();
        _;
    }

    /// @notice Burn OHM from the treasury
    /// @param amount_ Amount of OHM to burn
    function burnFromTreasury(
        uint256 amount_,
        bytes32 category_
    ) external onlyRole("burner_admin") onlyApproved(category_) {
        // Withdraw OHM from the treasury
        TRSRY.increaseWithdrawApproval(address(this), ohm, amount_);
        TRSRY.withdrawReserves(address(this), ohm, amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);

        // Emit a burn event
        emit Burn(address(TRSRY), category_, amount_);
    }

    /// @notice Burn OHM from an address
    /// @param from_ Address to burn OHM from
    /// @param amount_ Amount of OHM to burn
    /// @dev Burning OHM from an address requires it to have approved the MINTR for their OHM.
    ///      Here, we transfer from the user and burn from this address to avoid approving a
    ///      a different contract.
    function burnFrom(
        address from_,
        uint256 amount_,
        bytes32 category_
    ) external onlyRole("burner_admin") onlyApproved(category_) {
        // Transfer OHM from the user to this contract
        ohm.safeTransferFrom(from_, address(this), amount_);

        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);

        // Emit a burn event
        emit Burn(from_, category_, amount_);
    }

    /// @notice Burn OHM in this contract
    /// @param amount_ Amount of OHM to burn
    function burn(
        uint256 amount_,
        bytes32 category_
    ) external onlyRole("burner_admin") onlyApproved(category_) {
        // Burn the OHM
        MINTR.burnOhm(address(this), amount_);

        // Emit a burn event
        emit Burn(address(this), category_, amount_);
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Add a category to the list of approved burn categories
    /// @param category_ Category to add
    function addCategory(bytes32 category_) external onlyRole("burner_admin") {
        if (categoryApproved[category_]) revert Burner_CategoryApproved();
        categories.push(category_);
        categoryApproved[category_] = true;

        emit CategoryAdded(category_);
    }

    /// @notice Remove a category from the list of approved burn categories
    /// @param category_ Category to remove
    function removeCategory(bytes32 category_) external onlyRole("burner_admin") {
        if (!categoryApproved[category_]) revert Burner_CategoryNotApproved();
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

    /// @notice Get the list of approved burn categories
    function getCategories() external view returns (bytes32[] memory) {
        return categories;
    }
}

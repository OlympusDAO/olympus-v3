// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IReserveWrapper} from "src/policies/interfaces/IReserveWrapper.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ERC4626} from "@solmate-6.2.0/mixins/ERC4626.sol";
import {SafeTransferLib} from "@solmate-6.2.0/utils/SafeTransferLib.sol";

// Bophades
import {Kernel, Policy, Keycode, Permissions, toKeycode} from "src/Kernel.sol";

// Modules
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @title  ReserveWrapper
/// @notice Periodic task to wrap the reserve tokens in the TRSRY module into sReserve tokens
contract ReserveWrapper is Policy, PolicyEnabler, IPeriodicTask, IReserveWrapper {
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    // Modules
    TRSRYv1 public TRSRY;

    ERC20 internal immutable _RESERVE;
    ERC4626 internal immutable _SRESERVE;

    // ========== CONSTRUCTOR ========== //

    constructor(address kernel_, address reserve_, address sReserve_) Policy(Kernel(kernel_)) {
        // Validate that the reserve address is not null
        if (reserve_ == address(0)) revert ReserveWrapper_ZeroAddress();

        // Validate that the sReserve asset is the same as the reserve
        if (address(ERC4626(sReserve_).asset()) != reserve_) revert ReserveWrapper_AssetMismatch();

        _RESERVE = ERC20(reserve_);
        _SRESERVE = ERC4626(sReserve_);
    }

    // ========== POLICY FUNCTIONS ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("ROLES");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        (uint8 TRSRY_MAJOR, ) = TRSRY.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1, 1]);
        if (ROLES_MAJOR != 1 || TRSRY_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode TRSRY_KEYCODE = TRSRY.KEYCODE();

        permissions = new Permissions[](2);
        permissions[0] = Permissions(TRSRY_KEYCODE, TRSRY.withdrawReserves.selector);
        permissions[1] = Permissions(TRSRY_KEYCODE, TRSRY.increaseWithdrawApproval.selector);
    }

    /// @notice Returns the version of the policy.
    ///
    /// @return major The major version of the policy.
    /// @return minor The minor version of the policy.
    function VERSION() external pure returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // ========== FUNCTIONS ========== //

    /// @inheritdoc IReserveWrapper
    function getReserve() external view override returns (address) {
        return address(_RESERVE);
    }

    /// @inheritdoc IReserveWrapper
    function getSReserve() external view override returns (address) {
        return address(_SRESERVE);
    }

    // ========== PERIODIC TASK ========== //

    /// @inheritdoc IPeriodicTask
    function execute() external override onlyRole(HEART_ROLE) {
        // Skip if the policy is not enabled
        if (!isEnabled) return;

        // Get the reserve balance from the TRSRY
        uint256 reserveBalance = _RESERVE.balanceOf(address(TRSRY));

        // Skip if the reserve balance is 0
        if (reserveBalance == 0) {
            return;
        }

        // Skip if depositing the balance would result in zero shares (as we don't want this to revert)
        if (_SRESERVE.previewDeposit(reserveBalance) == 0) {
            return;
        }

        // Approve withdrawing the reserves from the TRSRY
        TRSRY.increaseWithdrawApproval(address(this), _RESERVE, reserveBalance);

        // Withdraw the reserves from the TRSRY
        TRSRY.withdrawReserves(address(this), _RESERVE, reserveBalance);

        // Wrap into sReserve and deposit into the TRSRY
        _RESERVE.safeApprove(address(_SRESERVE), reserveBalance);
        _SRESERVE.deposit(reserveBalance, address(TRSRY));

        emit ReserveWrapped(address(_RESERVE), address(_SRESERVE), reserveBalance);
    }

    // ========== ERC165 INTERFACE SUPPORT ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(PolicyEnabler, IPeriodicTask) returns (bool) {
        return
            interfaceId == type(IPeriodicTask).interfaceId ||
            interfaceId == type(IReserveWrapper).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

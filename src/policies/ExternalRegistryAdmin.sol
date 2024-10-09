// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "src/modules/ROLES/OlympusRoles.sol";
import {EXREGv1} from "src/modules/EXREG/EXREG.v1.sol";
import {Kernel, Policy, Keycode, toKeycode, Permissions} from "src/Kernel.sol";

/// @title  ExternalRegistryAdmin
/// @notice This policy is used to register and deregister contracts in the EXREG module.
contract ExternalRegistryAdmin is Policy, RolesConsumer {
    // ============ ERRORS ============ //

    /// @notice Thrown when the address is invalid
    error Params_InvalidAddress();

    /// @notice Thrown when the contract is not activated as a policy
    error OnlyPolicyActive();

    // ============ STATE ============ //

    /// @notice The EXREG module
    EXREGv1 internal _EXREG;

    /// @notice The role for the external registry admin
    bytes32 public constant EXTERNAL_REGISTRY_ADMIN_ROLE = "external_registry_admin";

    // ============ CONSTRUCTOR ============ //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Validate that the kernel address is valid
        if (kernel_ == address(0)) revert Params_InvalidAddress();
    }

    // ============ POLICY FUNCTIONS ============ //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](2);
        dependencies[0] = toKeycode("EXREG");
        dependencies[1] = toKeycode("ROLES");

        _EXREG = EXREGv1(getModuleAddress(dependencies[0]));
        ROLES = ROLESv1(getModuleAddress(dependencies[1]));

        // Verify the supported version
        bytes memory expected = abi.encode([1, 1]);
        (uint8 EXREG_MAJOR, ) = _EXREG.VERSION();
        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();
        if (EXREG_MAJOR != 1 || ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);

        return dependencies;
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory permissions)
    {
        Keycode exregKeycode = toKeycode("EXREG");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(exregKeycode, EXREGv1.registerContract.selector);
        permissions[1] = Permissions(exregKeycode, EXREGv1.deregisterContract.selector);

        return permissions;
    }

    /// @notice The version of the policy
    function VERSION() external pure returns (uint8) {
        return 1;
    }

    // ============ MODIFIERS ============ //

    /// @notice Modifier to check that the contract is activated as a policy
    modifier onlyPolicyActive() {
        if (!kernel.isPolicyActive(this)) revert OnlyPolicyActive();
        _;
    }

    // ============ ADMIN FUNCTIONS ============ //

    /// @notice Register a contract in the external registry
    /// @dev    This function will revert if:
    ///         - This contract is not activated as a policy
    ///         - The caller does not have the required role
    ///         - The EXREG module reverts
    ///
    /// @param  name_ The name of the contract
    /// @param  contractAddress_ The address of the contract
    function registerContract(
        bytes5 name_,
        address contractAddress_
    ) external onlyPolicyActive onlyRole(EXTERNAL_REGISTRY_ADMIN_ROLE) {
        _EXREG.registerContract(name_, contractAddress_);
    }

    /// @notice Deregister a contract in the external registry
    /// @dev    This function will revert if:
    ///         - This contract is not activated as a policy
    ///         - The caller does not have the required role
    ///         - The EXREG module reverts
    ///
    /// @param  name_ The name of the contract
    function deregisterContract(
        bytes5 name_
    ) external onlyPolicyActive onlyRole(EXTERNAL_REGISTRY_ADMIN_ROLE) {
        _EXREG.deregisterContract(name_);
    }

    // ============ VIEW FUNCTIONS ============ //

    /// @notice Get the address of the contract
    /// @dev    This function will revert if:
    ///         - This contract is not activated as a policy
    ///         - The EXREG module reverts
    ///
    /// @return The address of the contract
    function getContract(bytes5 name_) external view onlyPolicyActive returns (address) {
        return _EXREG.getContract(name_);
    }

    /// @notice Get the names of the contracts
    /// @dev    This function will revert if:
    ///         - This contract is not activated as a policy
    ///         - The EXREG module reverts
    ///
    /// @return The names of the contracts
    function getContractNames() external view onlyPolicyActive returns (bytes5[] memory) {
        return _EXREG.getContractNames();
    }
}

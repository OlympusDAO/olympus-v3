// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

/// @notice Actions to trigger state changes in the kernel. Passed by the executor
enum Actions {
    InstallModule,
    UpgradeModule,
    ActivatePolicy,
    DeactivatePolicy,
    ChangeExecutor,
    MigrateKernel
}

/// @notice Five-byte identifier for a Kernel module.
type Keycode is bytes5;

/// @notice Public Kernel API, with module and Policy references expressed as addresses.
interface IKernel {
    /// @notice Returns the authority that executes Kernel actions.
    /// @return executor Address holding execution authority.
    function executor() external view returns (address executor);

    /// @notice Returns an installed module's keycode by index.
    /// @param index Index in the installed-keycode list.
    /// @return keycode Installed module identifier.
    function allKeycodes(uint256 index) external view returns (Keycode keycode);

    /// @notice Returns the installed module for a keycode.
    /// @param keycode Module identifier to query.
    /// @return module Installed module address, or zero when absent.
    function getModuleForKeycode(Keycode keycode) external view returns (address module);

    /// @notice Returns the keycode assigned to a module.
    /// @param module Module address to query.
    /// @return keycode Assigned identifier, or zero when absent.
    function getKeycodeForModule(address module) external view returns (Keycode keycode);

    /// @notice Returns a Policy that depends on a module.
    /// @param keycode Module identifier to query.
    /// @param index Index in the module's dependent list.
    /// @return policy Dependent Policy address.
    function moduleDependents(
        Keycode keycode,
        uint256 index
    ) external view returns (address policy);

    /// @notice Returns a Policy's index in a module's dependent list.
    /// @param keycode Module identifier to query.
    /// @param policy Policy address to query.
    /// @return index Stored index; use moduleDependents to confirm membership.
    function getDependentIndex(
        Keycode keycode,
        address policy
    ) external view returns (uint256 index);

    /// @notice Returns whether a Policy may call a module function.
    /// @param keycode Module identifier to query.
    /// @param policy Policy address to query.
    /// @param selector Module function selector.
    /// @return permitted Whether the function permission is granted.
    function modulePermissions(
        Keycode keycode,
        address policy,
        bytes4 selector
    ) external view returns (bool permitted);

    /// @notice Returns an active Policy by index.
    /// @param index Index in the active-Policy list.
    /// @return policy Active Policy address.
    function activePolicies(uint256 index) external view returns (address policy);

    /// @notice Returns a Policy's stored index in the active list.
    /// @param policy Policy address to query.
    /// @return index Stored index; use isPolicyActive to confirm membership.
    function getPolicyIndex(address policy) external view returns (uint256 index);

    /// @notice Returns whether a Policy is active in this Kernel.
    /// @param policy Policy address to query.
    /// @return active Whether the Policy retains active membership.
    function isPolicyActive(address policy) external view returns (bool active);

    /// @notice Executes a Kernel action against its target.
    /// @param action Action selected by the executor.
    /// @param target Module, Policy, executor or replacement Kernel address, according to the action.
    function executeAction(Actions action, address target) external;
}

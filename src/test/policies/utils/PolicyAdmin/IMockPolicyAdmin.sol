// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Common surface for the `PolicyAdmin` and `PolicyAdminOptimized` test harnesses.
/// @dev    Lets a single copy of the test logic target either mix-in through this interface.
interface IMockPolicyAdmin {
    /// @notice A function gated by the `onlyAdminRole` modifier.
    function gatedToAdminRole() external view returns (bool);

    /// @notice A function gated by the `onlyEmergencyRole` modifier.
    function gatedToEmergencyRole() external view returns (bool);

    /// @notice A function gated by the `onlyManagerRole` modifier.
    function gatedToManagerRole() external view returns (bool);

    /// @notice A function gated by the `onlyEmergencyOrAdminRole` modifier.
    function gatedToEmergencyOrAdminRole() external view returns (bool);

    /// @notice A function gated by the `onlyManagerOrAdminRole` modifier.
    function gatedToManagerOrAdminRole() external view returns (bool);
}

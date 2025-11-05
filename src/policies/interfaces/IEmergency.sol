// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.15;

/// @title IEmergency
/// @notice Interface for the Emergency policy
interface IEmergency {
    /// @notice Emergency shutdown of treasury withdrawals and minting
    function shutdown() external;

    /// @notice Emergency shutdown of treasury withdrawals
    function shutdownWithdrawals() external;

    /// @notice Emergency shutdown of minting
    function shutdownMinting() external;

    /// @notice Restart treasury withdrawals and minting after shutdown
    function restart() external;

    /// @notice Restart treasury withdrawals after shutdown
    function restartWithdrawals() external;

    /// @notice Restart minting after shutdown
    function restartMinting() external;
}

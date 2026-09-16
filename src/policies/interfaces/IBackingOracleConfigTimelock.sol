// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ITimelockQueue} from "src/policies/interfaces/utils/ITimelockQueue.sol";

/// @title IBackingOracleConfigTimelock
/// @notice The timelocked configuration surface of the BackingOracle policy.
/// @dev A proposer queues a backing update via `queueSetBacking`, and the update is applied
///      when the queued action is executed through the inherited `ITimelockQueue` surface.
///      Execution is permissionless once the timelock delay elapses; the emergency role can
///      cancel queued actions.
interface IBackingOracleConfigTimelock is ITimelockQueue {
    // ============ TIMELOCK MANAGEMENT ============ //

    /// @notice Set the timelock delay applied to future queued actions.
    /// @dev Already-queued actions keep the delay they were queued with. Intended to be
    ///      callable only by the admin role.
    ///
    /// @param delay_ The new timelock delay in seconds.
    function setTimelockDelay(uint48 delay_) external;

    // ============ QUEUE ============ //

    /// @notice Queue a timelocked update of the backing value (the reserve per OHM, 18 decimals).
    /// @dev The backing value is not updated until the queued action is executed. The backing
    ///      change threshold is validated against the current backing value both when the action
    ///      is queued and when it is executed, because the current backing may change between the
    ///      two. Intended to be callable only by the backing_admin or admin role.
    ///
    /// @param newBacking_ The new backing value (18 decimals).
    /// @return actionId_ The queued action ID.
    function queueSetBacking(uint256 newBacking_) external returns (uint64 actionId_);
}

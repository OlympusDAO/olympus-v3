// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interfaces
import {IBackingOracle} from "src/policies/interfaces/IBackingOracle.sol";
import {IConfigTimelockBatchQueue} from "src/policies/interfaces/utils/IConfigTimelockBatchQueue.sol";

/// @title Backing Oracle Configuration Timelock
/// @notice Delayed proposals for one immutable oracle, executed through its selected operator.
interface IBackingOracleConfigTimelock is IConfigTimelockBatchQueue {
    /// @notice The queue requires a nonzero Kernel.
    error BackingOracleTimelock_ZeroKernelAddress();
    /// @notice The queue is inactive in its Kernel.
    error BackingOracleTimelock_PolicyNotActive(address policy);
    /// @notice The oracle lacks a consumed interface.
    error BackingOracleTimelock_InvalidBackingOracle(address oracle);
    /// @notice Enable/disable require empty data.
    error BackingOracleTimelock_InvalidEnablerData();

    /// @notice Return the immutable backing oracle.
    /// @return oracle The oracle configured by this queue.
    function backingOracle() external view returns (IBackingOracle oracle);

    /// @notice Queue a bounded backing update through the selected operator.
    /// @param newBacking_ New reserve value per OHM (18 decimals).
    /// @return actionId_ ID of the delayed action.
    function queueSetBacking(uint256 newBacking_) external returns (uint64 actionId_);
}

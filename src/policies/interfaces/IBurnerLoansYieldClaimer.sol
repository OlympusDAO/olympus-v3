// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claimer Interface
/// @notice Fail-soft Heart task for gas-bounded Burner Loans yield claims.
interface IBurnerLoansYieldClaimer {
    /// @notice A required constructor address is zero.
    error BurnerLoansYieldClaimer_ZeroAddress();

    /// @notice The configured target lacks required claim or asset-registry view support.
    /// @param burnerLoans Invalid Burner Loans target.
    error BurnerLoansYieldClaimer_InvalidBurnerLoans(address burnerLoans);

    /// @notice The configured Burner Loans target belongs to a different Kernel.
    /// @param expectedKernel Kernel that manages the YieldClaimer.
    /// @param actualKernel Kernel reported by the Burner Loans target.
    error BurnerLoansYieldClaimer_KernelMismatch(address expectedKernel, address actualKernel);

    /// @notice The configured gas limit for one complete task execution is zero.
    error BurnerLoansYieldClaimer_InvalidExecutionGasLimit();

    /// @notice The gas-bounded task body was called by an account other than this contract.
    error BurnerLoansYieldClaimer_OnlySelf();

    /// @notice Emitted when an authorized account changes the complete task gas limit.
    /// @param gasLimit New complete task gas limit.
    event ExecutionGasLimitSet(uint32 gasLimit);

    /// @notice Emitted when the gas-bounded task body fails.
    /// @param reason First four bytes of the task's bounded revert data.
    event ExecutionFailed(bytes4 reason);

    /// @notice Emitted when an individual asset claim fails atomically.
    /// @param asset Collateral asset whose claim failed.
    /// @param selector Underlying revert prefix.
    event YieldAssetClaimFailed(address indexed asset, bytes4 selector);

    /// @notice Sets the gas forwarded to one complete task execution.
    /// @dev Reverts when `gasLimit_` is zero or the caller lacks both the OCG admin and
    ///      `burner_loans_admin` roles.
    /// @param gasLimit_ New complete task gas limit.
    function setExecutionGasLimit(uint32 gasLimit_) external;

    /// @notice Executes the gas-bounded task body through an external self-call.
    /// @dev Reverts unless called by this contract itself. The outer `execute` call catches failure.
    function selfExecuteTask() external;

    /// @notice Returns the Burner Loans policy used as the claim source.
    /// @return burnerLoans_ Burner Loans policy called by the periodic task.
    function burnerLoans() external view returns (address burnerLoans_);

    /// @notice Returns the gas forwarded to one complete task execution.
    /// @return gasLimit_ Complete task gas limit.
    function executionGasLimit() external view returns (uint32 gasLimit_);
}

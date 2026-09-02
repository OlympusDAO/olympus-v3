// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claimer Interface
/// @notice Fail-soft Heart task for gas-bounded all-asset Burner Loans yield claims.
interface IBurnerLoansYieldClaimer {
    /// @notice A required constructor address is zero.
    error BurnerLoansYieldClaimer_ZeroAddress();

    /// @notice The configured target does not advertise the claim-only Burner Loans interface.
    /// @param burnerLoans Invalid Burner Loans target.
    error BurnerLoansYieldClaimer_InvalidBurnerLoans(address burnerLoans);

    /// @notice The configured Burner Loans target belongs to a different Kernel.
    /// @param expectedKernel Kernel that manages the YieldClaimer.
    /// @param actualKernel Kernel reported by the Burner Loans target.
    error BurnerLoansYieldClaimer_KernelMismatch(address expectedKernel, address actualKernel);

    /// @notice The configured gas forwarded to `BurnerLoans.claimYield` is zero.
    error BurnerLoansYieldClaimer_InvalidExecutionGasLimit();

    /// @notice Emitted when an authorized account changes the gas forwarded to the batch claim.
    /// @param gasLimit New claim gas limit.
    event ExecutionGasLimitSet(uint32 gasLimit);

    /// @notice Emitted when a gas-bounded yield claim fails.
    /// @param burnerLoans Burner Loans policy whose aggregate claim failed.
    /// @param selector First four bytes of the underlying revert data, right-padded if shorter.
    event YieldClaimFailed(address indexed burnerLoans, bytes4 selector);

    /// @notice Sets the gas forwarded to `BurnerLoans.claimYield`.
    /// @dev Reverts when `gasLimit_` is zero or the caller lacks both the OCG admin and
    ///      `burner_loans_admin` roles.
    /// @param gasLimit_ New gas limit forwarded to the aggregate claim.
    function setExecutionGasLimit(uint32 gasLimit_) external;

    /// @notice Returns the Burner Loans policy used as the claim source.
    /// @return burnerLoans_ Burner Loans policy called by the periodic task.
    function burnerLoans() external view returns (address burnerLoans_);

    /// @notice Returns the gas forwarded to the all-asset yield claim.
    /// @return gasLimit_ Gas limit forwarded to `BurnerLoans.claimYield`.
    function executionGasLimit() external view returns (uint32 gasLimit_);
}

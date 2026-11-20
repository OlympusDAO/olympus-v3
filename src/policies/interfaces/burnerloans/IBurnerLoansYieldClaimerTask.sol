// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Burner Loans Yield Claimer Task Interface
/// @notice Fail-soft Heart task for gas-bounded Burner Loans yield claims.
interface IBurnerLoansYieldClaimerTask {
    // ========== EVENTS ========== //

    /// @notice Emitted when an authorized account changes the complete task gas limit.
    /// @param gasLimit New complete task gas limit.
    event ExecutionGasLimitSet(uint32 gasLimit);

    /// @notice Emitted when the minimum gas needed to start another claim attempt changes.
    /// @param gasLimit Minimum gas remaining before the asset lookup.
    event MinimumGasToAttemptSet(uint32 gasLimit);

    /// @notice Emitted when the gas retained after each claim attempt changes.
    /// @param gasLimit Gas reserved for task cleanup.
    event GasReserveSet(uint32 gasLimit);

    /// @notice Emitted when an authorized account selects the next registered asset to attempt.
    /// @param index Selected registry index.
    event NextAssetIndexSet(uint256 index);

    /// @notice Emitted when the gas-bounded task body fails.
    /// @param reason First four bytes of the task's bounded revert data.
    event ExecutionFailed(bytes4 reason);

    /// @notice Emitted when an individual asset claim fails atomically.
    /// @param asset Collateral asset whose claim failed.
    /// @param selector Underlying revert prefix.
    event YieldAssetClaimFailed(address indexed asset, bytes4 selector);

    // ========== ERRORS ========== //

    /// @notice The configured Core lacks required interfaces or has incompatible metadata.
    /// @param core Invalid Core candidate.
    error BurnerLoansYieldClaimer_InvalidCore(address core);

    /// @notice The configured gas limit for one complete task execution is zero.
    error BurnerLoansYieldClaimer_InvalidExecutionGasLimit();

    /// @notice The attempt threshold does not exceed the gas retained for task cleanup.
    error BurnerLoansYieldClaimer_InvalidMinimumGasToAttempt();

    /// @notice The cleanup gas reserve is below the supported minimum or reaches the threshold.
    error BurnerLoansYieldClaimer_InvalidGasReserve();

    /// @notice The selected cursor is outside the current asset registry.
    /// @param index Requested cursor.
    /// @param assetCount Current number of registered assets.
    error BurnerLoansYieldClaimer_InvalidAssetIndex(uint256 index, uint256 assetCount);

    /// @notice The gas-bounded task body was called by an account other than this contract.
    error BurnerLoansYieldClaimer_OnlySelf();

    // ========== FUNCTIONS ========== //

    /// @notice Sets the gas forwarded to one complete task execution.
    /// @dev An unchanged valid value emits no event.
    ///
    /// @param gasLimit_ New complete task gas limit.
    function setExecutionGasLimit(uint32 gasLimit_) external;

    /// @notice Sets the minimum gas remaining before attempting another registered asset.
    /// @dev Admin or `burner_loans_admin` only. Must exceed the cleanup reserve. Callable while
    ///      locally disabled while Kernel-active. An unchanged valid value emits no event.
    /// @param gasLimit_ Minimum gas remaining before another asset attempt.
    function setMinimumGasToAttempt(uint32 gasLimit_) external;

    /// @notice Sets the gas retained after each isolated yield claim.
    /// @dev Admin or `burner_loans_admin` only. Must be at least the implementation's supported
    ///      cleanup minimum and below the current attempt threshold. Callable while locally
    ///      disabled while Kernel-active. An unchanged valid value emits no event.
    /// @param gasLimit_ Gas retained for cursor persistence and task cleanup.
    function setGasReserve(uint32 gasLimit_) external;

    /// @notice Selects the next registered asset to attempt. Zero resets the cursor.
    /// @dev Admin or `burner_loans_admin` only. A nonzero index must be below the live registry
    ///      count. Callable while locally disabled while Kernel-active. An unchanged valid value
    ///      emits no event.
    /// @param index_ Registry index to attempt next, or zero to reset.
    function setNextAssetIndex(uint256 index_) external;

    /// @notice Returns the gas forwarded to one complete task execution.
    /// @return gasLimit_ Complete task gas limit.
    function executionGasLimit() external view returns (uint32 gasLimit_);

    /// @notice Returns the minimum gas remaining before another claim attempt starts.
    /// @return gasLimit_ Configured attempt threshold.
    function minimumGasToAttempt() external view returns (uint32 gasLimit_);

    /// @notice Returns the gas retained after each isolated claim attempt.
    /// @return gasLimit_ Configured cleanup reserve.
    function gasReserve() external view returns (uint32 gasLimit_);

    /// @notice Returns the stored cursor; execution normalizes it against the live registry count.
    /// @return index_ Registered-asset index attempted first on the next execution.
    function nextAssetIndex() external view returns (uint256 index_);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/// @title Revenue Distributor Task Interface
/// @notice Gas-bounded Heart task that rotates through active distributor assets.
interface IRevenueDistributorTask {
    /// @notice The distributor lacks the required interface or is inactive when the task is enabled.
    /// @param distributor Invalid distributor address.
    error RevenueDistributorTask_InvalidDistributor(address distributor);

    /// @notice The distributor belongs to a different Kernel.
    /// @param expectedKernel Kernel passed to the task constructor.
    /// @param actualKernel Kernel reported by the distributor.
    error RevenueDistributorTask_KernelMismatch(address expectedKernel, address actualKernel);

    /// @notice The task is not active in its current Kernel.
    error RevenueDistributorTask_PolicyInactive();

    /// @notice The complete task gas limit is zero.
    error RevenueDistributorTask_InvalidExecutionGasLimit();

    /// @notice The attempt threshold does not exceed the gas retained for task cleanup.
    error RevenueDistributorTask_InvalidMinimumGasToAttempt();

    /// @notice The cleanup gas reserve is zero or reaches the current attempt threshold.
    error RevenueDistributorTask_InvalidGasReserve();

    /// @notice The selected cursor is outside the current active asset set.
    /// @param index Requested cursor.
    /// @param assetCount Current number of active assets.
    error RevenueDistributorTask_InvalidAssetIndex(uint256 index, uint256 assetCount);

    /// @notice A caller other than the task attempted the isolated execution entry point.
    error RevenueDistributorTask_OnlySelf();

    /// @notice The complete task gas limit changed.
    /// @param gasLimit Gas forwarded to the task's self-call.
    event ExecutionGasLimitSet(uint32 gasLimit);

    /// @notice The minimum gas needed to start another asset attempt changed.
    /// @param gasLimit Minimum gas remaining before the asset lookup.
    event MinimumGasToAttemptSet(uint32 gasLimit);

    /// @notice The gas retained after each asset attempt changed.
    /// @param gasLimit Gas reserved for task cleanup.
    event GasReserveSet(uint32 gasLimit);

    /// @notice An authorized caller selected the next active asset to attempt.
    /// @param index Selected cursor.
    event NextAssetIndexSet(uint256 index);

    /// @notice The bounded task self-call failed.
    /// @param reason First four bytes of the returned error data, if any.
    event ExecutionFailed(bytes4 reason);

    /// @notice Distribution of one asset failed during task execution.
    /// @param asset Asset whose distribution failed.
    /// @param selector First four bytes of the returned error data, if any.
    event AssetDistributionFailed(address indexed asset, bytes4 selector);

    /// @notice Sets the gas forwarded to the complete periodic task.
    /// @dev Admin or revenue_distributor_admin only. An unchanged valid value emits no event.
    /// @param gasLimit_ Gas forwarded to the task's self-call.
    function setExecutionGasLimit(uint32 gasLimit_) external;

    /// @notice Sets the minimum gas remaining before attempting another asset.
    /// @dev Admin or revenue_distributor_admin only. Must exceed the task's cleanup reserve.
    ///      Callable while the task is disabled. An unchanged valid value emits no event.
    /// @param gasLimit_ Minimum gas remaining before another asset attempt.
    function setMinimumGasToAttempt(uint32 gasLimit_) external;

    /// @notice Sets the gas retained after each asset attempt.
    /// @dev Admin or revenue_distributor_admin only. Must be nonzero and below the current
    ///      minimum gas to attempt. Callable while the task is disabled. An unchanged valid value
    ///      emits no event.
    /// @param gasLimit_ Gas retained for task cleanup.
    function setGasReserve(uint32 gasLimit_) external;

    /// @notice Selects the next active asset to attempt. Zero resets the cursor.
    /// @dev Admin or revenue_distributor_admin only; index must be below the active asset count,
    ///      except zero is always valid. An unchanged valid value emits no event.
    /// @param index_ Active asset index to attempt next, or zero to reset.
    function setNextAssetIndex(uint256 index_) external;

    /// @notice Attempts active assets until each is visited or execution gas runs low.
    /// @dev Callable only through the task's self-call.
    function selfExecuteTask() external;

    /// @notice Returns the constructor-bound Revenue Distributor policy.
    /// @return Distributor policy address.
    function distributor() external view returns (address);

    /// @notice Returns the gas forwarded to the complete periodic task.
    /// @return Configured execution gas limit.
    function executionGasLimit() external view returns (uint32);

    /// @notice Returns the minimum gas remaining before another asset attempt starts.
    /// @return Configured attempt threshold.
    function minimumGasToAttempt() external view returns (uint32);

    /// @notice Returns the gas retained after each asset attempt.
    /// @return Configured cleanup reserve.
    function gasReserve() external view returns (uint32);

    /// @notice Returns the stored cursor; execution normalizes it if the active set shrinks.
    /// @return Stored index of the next asset to attempt.
    function nextAssetIndex() external view returns (uint256);
}

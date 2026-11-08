// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansConfig} from "src/policies/interfaces/burnerloans/IBurnerLoansConfig.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock
/// @notice Timelock implementation that may serve as Burner Loans Config's config operator.
/// @dev Burner Loans Config is the configurator of Burner Loans; this interface does not represent
///      a timelock that is bound directly to Burner Loans.
interface IBurnerLoansConfigTimelock {
    // ========== ERRORS ========== //

    /// @notice Thrown when Burner Loans Config is incompatible.
    /// @param burnerLoans The invalid Burner Loans Config policy address.
    error BurnerLoansConfigTimelock_InvalidBurnerLoansConfig(address burnerLoans);

    /// @notice Thrown when a configured module has an unsupported version.
    error BurnerLoansConfigTimelock_InvalidModuleVersion();

    /// @notice Thrown when a supported sub-action fails without an underlying error that can be
    ///         safely propagated.
    /// @param target The contract called by the sub-action.
    /// @param selector The function selector called on the target.
    error BurnerLoansConfigTimelock_SubActionCallFailed(address target, bytes4 selector);

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the Burner Loans Config policy targeted by this timelock.
    /// @return burnerLoans_ The Burner Loans Config policy.
    function burnerLoans() external view returns (IBurnerLoansConfig burnerLoans_);

    /// @notice Returns the minimum supported timelock delay.
    /// @return delay_ The minimum delay, in seconds.
    function MIN_TIMELOCK_DELAY() external view returns (uint48 delay_);

    /// @notice Returns the maximum supported timelock delay.
    /// @return delay_ The maximum delay, in seconds.
    function MAX_TIMELOCK_DELAY() external view returns (uint48 delay_);

    /// @notice Returns the execution window after the delay has elapsed.
    /// @return window_ The execution window, in seconds.
    function EXECUTION_WINDOW() external view returns (uint48 window_);

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues an asset fee-curve update.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete fee curve.
    /// @return actionId The queued action ID.
    function queueSetAssetFeeConfig(
        address asset_,
        IBurnerLoansRisk.AssetFeeConfig calldata config_
    ) external returns (uint64 actionId);

    /// @notice Queues an asset active debt cap update.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New active debt cap, in OHM decimals.
    /// @return actionId The queued action ID.
    function queueSetAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external returns (uint64 actionId);

    /// @notice Queues rescue of all unreserved tokens at execution time.
    /// @param token_ Token to rescue.
    /// @param destination_ Rescue recipient.
    /// @return actionId Queued action identifier.
    function queueRescue(address token_, address destination_) external returns (uint64 actionId);

    /// @notice Queues a change to the token form used for all DepositManager exits.
    /// @param asset_ Collateral asset to update.
    /// @param withdrawAsShares_ Whether future exits return the configured vault shares.
    /// @return actionId The queued action ID.
    function queueSetAssetWithdrawAsShares(
        address asset_,
        bool withdrawAsShares_
    ) external returns (uint64 actionId);

    /// @notice Queues a partial asset risk-configuration update.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Complete risk and term configuration.
    /// @return actionId The queued action ID.
    function queueSetAssetRiskConfig(
        address asset_,
        IBurnerLoansRisk.AssetRiskConfigInput calldata config_
    ) external returns (uint64 actionId);

    /// @notice Queues a batch of Burner Loans Config updates.
    /// @dev Every sub-action must target Burner Loans Config and use a supported setter.
    ///      The batch is validated and later executed atomically in array order.
    /// @param actions_ The Burner Loans Config sub-actions to queue.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

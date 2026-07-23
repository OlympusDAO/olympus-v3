// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansConfig} from "src/policies/interfaces/IBurnerLoansConfig.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Burner Loans Config Timelock
/// @notice Timelocked configuration surface for Burner Loans risk parameters.
interface IBurnerLoansConfigTimelock is ITimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when the Burner Loans policy address is zero.
    error BurnerLoansConfigTimelock_ZeroAddress();

    /// @notice Thrown when Burner Loans Config is incompatible.
    /// @param burnerLoans The invalid Burner Loans policy address.
    error BurnerLoansConfigTimelock_InvalidBurnerLoans(address burnerLoans);

    /// @notice Thrown when Burner Loans Config belongs to a different Kernel.
    /// @param configKernel The Kernel configured on Burner Loans Config.
    error BurnerLoansConfigTimelock_KernelMismatch(address configKernel);

    /// @notice Thrown when a configured module has an unsupported version.
    error BurnerLoansConfigTimelock_InvalidModuleVersion();

    /// @notice Thrown when a queued sub-action no longer matches its expected pre-state.
    /// @param actionId The queued action ID.
    /// @param index The sub-action index within the queued action.
    /// @param expectedHash The pre-state hash captured when the sub-action was queued.
    /// @param currentHash The live pre-state hash observed at execution.
    error BurnerLoansConfigTimelock_ConfigStateChanged(
        uint64 actionId,
        uint256 index,
        bytes32 expectedHash,
        bytes32 currentHash
    );

    // ========== STRUCTS ========== //

    /// @notice Partial update payload for asset-level risk and term configuration.
    /// @dev Fields are applied only when their matching selection boolean is true.
    /// @param collateralFactorBps New collateral factor, in bps.
    /// @param minCollateralRatioBps New minimum collateral ratio, in bps.
    /// @param backingMultiplierBps New backing multiplier, in bps.
    /// @param keeperRewardBps New keeper reward share, in bps.
    /// @param termLength New fixed term length, in seconds.
    /// @param maxMaturityHorizon New maximum maturity horizon, in seconds.
    /// @param maxKeeperReward New maximum keeper reward, in collateral token decimals.
    struct AssetRiskConfigUpdate {
        uint16 collateralFactorBps;
        uint16 minCollateralRatioBps;
        uint16 backingMultiplierBps;
        uint16 keeperRewardBps;
        uint48 termLength;
        uint48 maxMaturityHorizon;
        uint256 maxKeeperReward;
    }

    /// @notice Selects which fields in an asset risk update should be applied.
    /// @param collateralFactorBps Whether to apply `AssetRiskConfigUpdate.collateralFactorBps`.
    /// @param minCollateralRatioBps Whether to apply `AssetRiskConfigUpdate.minCollateralRatioBps`.
    /// @param backingMultiplierBps Whether to apply `AssetRiskConfigUpdate.backingMultiplierBps`.
    /// @param keeperRewardBps Whether to apply `AssetRiskConfigUpdate.keeperRewardBps`.
    /// @param termLength Whether to apply `AssetRiskConfigUpdate.termLength`.
    /// @param maxMaturityHorizon Whether to apply `AssetRiskConfigUpdate.maxMaturityHorizon`.
    /// @param maxKeeperReward Whether to apply `AssetRiskConfigUpdate.maxKeeperReward`.
    struct AssetRiskConfigUpdateSelection {
        bool collateralFactorBps;
        bool minCollateralRatioBps;
        bool backingMultiplierBps;
        bool keeperRewardBps;
        bool termLength;
        bool maxMaturityHorizon;
        bool maxKeeperReward;
    }

    /// @notice Selects which fields in a fee config update should be applied.
    /// @param baseFeeBps Whether to apply `AssetFeeConfig.baseFeeBps`.
    /// @param kinkBps Whether to apply `AssetFeeConfig.kinkBps`.
    /// @param preKinkSlopeBps Whether to apply `AssetFeeConfig.preKinkSlopeBps`.
    /// @param postKinkSlopeBps Whether to apply `AssetFeeConfig.postKinkSlopeBps`.
    struct FeeConfigUpdateSelection {
        bool baseFeeBps;
        bool kinkBps;
        bool preKinkSlopeBps;
        bool postKinkSlopeBps;
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the Burner Loans Config policy controlled by this timelock.
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
    /// @dev Reverts if the timelock policy is disabled.
    /// @param asset_ Collateral asset to update.
    /// @param config_ Partial fee curve update.
    /// @param selection_ Fields to apply from `config_`.
    /// @return actionId The queued action ID.
    function queueSetAssetFeeConfig(
        address asset_,
        IBurnerLoansConfig.AssetFeeConfig calldata config_,
        FeeConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId);

    /// @notice Queues an asset active debt cap update.
    /// @dev Reverts if the timelock policy is disabled.
    /// @param asset_ Collateral asset to update.
    /// @param debtCapOhm_ New active debt cap, in OHM decimals.
    /// @return actionId The queued action ID.
    function queueSetAssetDebtCap(
        address asset_,
        uint128 debtCapOhm_
    ) external returns (uint64 actionId);

    /// @notice Queues a partial asset risk-configuration update.
    /// @dev Reverts if the timelock policy is disabled.
    /// @param asset_ Collateral asset to update.
    /// @param update_ Partial risk and term update.
    /// @param selection_ Fields to apply from `update_`.
    /// @return actionId The queued action ID.
    function queueSetAssetRiskConfig(
        address asset_,
        AssetRiskConfigUpdate calldata update_,
        AssetRiskConfigUpdateSelection calldata selection_
    ) external returns (uint64 actionId);

    /// @notice Queues a batch of Burner Loans configuration updates.
    /// @dev Every sub-action must target Burner Loans Config and use a supported setter.
    ///      Reverts if the timelock policy is disabled. The batch is validated and later
    ///      executed atomically in array order.
    /// @param actions_ The Burner Loans configuration sub-actions to queue.
    /// @return actionId The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

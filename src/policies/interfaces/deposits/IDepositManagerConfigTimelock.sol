// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Deposit Manager Config Timelock
/// @notice Timelocked configuration operator for mutable Deposit Manager settings.
interface IDepositManagerConfigTimelock is ITimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when the Deposit Manager address is zero.
    error DepositManagerConfigTimelock_ZeroAddress();

    /// @notice Thrown when the target does not implement the required interfaces.
    /// @param depositManager Invalid target address.
    error DepositManagerConfigTimelock_InvalidDepositManager(address depositManager);

    /// @notice Thrown when a policy required for queueing or execution is not active in the Kernel.
    /// @param policy Inactive policy address.
    error DepositManagerConfigTimelock_PolicyInactive(address policy);

    /// @notice Thrown when the target belongs to another Kernel.
    /// @param targetKernel Kernel configured on the target.
    error DepositManagerConfigTimelock_KernelMismatch(address targetKernel);

    /// @notice Thrown when a required module version is unsupported.
    error DepositManagerConfigTimelock_InvalidModuleVersion();

    // ========== VIEW FUNCTIONS ========== //

    /// @notice Returns the controlled Deposit Manager.
    /// @return manager_ Deposit Manager target.
    function depositManager() external view returns (IDepositManager manager_);

    /// @notice Returns the minimum supported timelock delay.
    function MIN_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Returns the maximum supported timelock delay.
    function MAX_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Returns the execution window after the delay.
    function EXECUTION_WINDOW() external view returns (uint48);

    // ========== QUEUE FUNCTIONS ========== //

    /// @notice Queues creation of a new asset-period route on the Deposit Manager.
    /// @dev Route creation starts enabled after timelock execution. Queueing requires a
    ///      configured asset, nonzero period, registered operator holding `deposit_operator`,
    ///      and an absent route. Admin or deposit_manager_admin may queue; execution is
    ///      permissionless after maturity.
    /// @param asset_ The configured underlying asset.
    /// @param depositPeriod_ The deposit period, in months.
    /// @param operator_ The registered operator holding the deposit_operator role.
    /// @return actionId Queued action identifier.
    function queueAddAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external returns (uint64 actionId);

    /// @notice Queues a deposit-cap update.
    /// @param asset_ Asset whose deposit cap will be updated.
    /// @param depositCap_ New deposit cap in underlying-asset units.
    /// @return actionId Queued action identifier.
    function queueSetAssetDepositCap(
        IERC20 asset_,
        uint256 depositCap_
    ) external returns (uint64 actionId);

    /// @notice Queues a minimum-deposit update.
    /// @param asset_ Asset whose minimum deposit will be updated.
    /// @param minimumDeposit_ New minimum deposit in underlying-asset units.
    /// @return actionId Queued action identifier.
    function queueSetAssetMinimumDeposit(
        IERC20 asset_,
        uint256 minimumDeposit_
    ) external returns (uint64 actionId);

    /// @notice Queues an explicit share-withdrawal requirement update.
    /// @param asset_ Asset whose withdrawal requirement will be updated.
    /// @param required_ Whether underlying withdrawals should be disabled explicitly.
    /// @return actionId Queued action identifier.
    function queueSetAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) external returns (uint64 actionId);

    /// @notice Queues enablement of an existing asset period.
    /// @param asset_ Asset whose period will be enabled.
    /// @param depositPeriod_ Deposit period to enable.
    /// @param operator_ Operator configured for the asset period.
    /// @return actionId Queued action identifier.
    function queueEnableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external returns (uint64 actionId);

    /// @notice Queues disablement of an existing asset period.
    /// @param asset_ Asset whose period will be disabled.
    /// @param depositPeriod_ Deposit period to disable.
    /// @param operator_ Operator configured for the asset period.
    /// @return actionId Queued action identifier.
    function queueDisableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external returns (uint64 actionId);

    /// @notice Queues an atomic batch of non-conflicting supported Deposit Manager updates.
    /// @param actions_ Supported actions to queue atomically.
    /// @return actionId Queued batch identifier.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

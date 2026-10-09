// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IRevenueDistributor} from "src/policies/interfaces/IRevenueDistributor.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title Revenue Distributor Config Timelock Interface
/// @notice Delayed authority for asset distributions and rescue.
/// @dev Admin and revenue_distributor_admin may queue configuration and rescue. Execution
///      is permissionless after delay.
interface IRevenueDistributorConfigTimelock is ITimelockBatchQueue {
    /// @notice The bound distributor is zero or does not expose the required interfaces.
    /// @param distributor Invalid distributor address.
    error RevenueDistributorConfigTimelock_InvalidDistributor(address distributor);

    /// @notice The bound distributor belongs to a different Kernel.
    /// @param targetKernel Kernel reported by the distributor.
    error RevenueDistributorConfigTimelock_KernelMismatch(address targetKernel);

    /// @notice A required policy is inactive in the Kernel.
    /// @param policy Inactive policy address.
    error RevenueDistributorConfigTimelock_PolicyInactive(address policy);

    /// @notice A queued target, selector, or payload is unsupported.
    /// @param target Action target address.
    /// @param selector Action function selector.
    error RevenueDistributorConfigTimelock_InvalidAction(address target, bytes4 selector);

    /// @notice Returns the immutable distributor target.
    /// @return distributor_ Bound distributor address.
    function distributor() external view returns (address distributor_);

    /// @notice Queues a complete asset distribution, including first listing and reactivation.
    /// @param asset_ Asset to configure.
    /// @param repurchaseBps_ Yield-repurchase allocation in basis points.
    /// @param routes_ Routes to non-Treasury recipients.
    /// @return actionId Queued action identifier.
    function queueSetAssetRoutes(
        address asset_,
        uint16 repurchaseBps_,
        IRevenueDistributor.AssetRoute[] calldata routes_
    ) external returns (uint64 actionId);

    /// @notice Queues disablement of an active managed asset.
    /// @param asset_ Asset whose route is retired.
    /// @return actionId Queued action identifier.
    function queueDisableAssetRoutes(address asset_) external returns (uint64 actionId);

    /// @notice Queues a global yield-recipient change.
    /// @param recipient_ Proposed yield-repurchase recipient.
    /// @return actionId Queued action identifier.
    function queueSetYieldRecipient(address recipient_) external returns (uint64 actionId);

    /// @notice Queues full execution-time balance rescue of a never-listed asset.
    /// @param asset_ Never-listed asset to recover.
    /// @param destination_ Recipient of the recovered tokens.
    /// @return actionId Queued action identifier.
    function queueRescue(address asset_, address destination_) external returns (uint64 actionId);

    /// @notice Queues a delayed rescue of an exact amount owed to one payout recipient.
    /// @dev Validates the current combined entitlement; execution rechecks current routing.
    /// @param asset_ Token owed.
    /// @param recipient_ Recipient currently owed the pending payout.
    /// @param destination_ Recipient of the rescued tokens.
    /// @param amount_ Exact positive amount, at most pendingPayout(asset_, recipient_).
    /// @return actionId Queued action identifier.
    function queueRescuePendingPayout(
        address asset_,
        address recipient_,
        address destination_,
        uint256 amount_
    ) external returns (uint64 actionId);

    /// @notice Queues an atomic batch of compatible distributor actions.
    /// @param actions_ Ordered actions executed atomically after the delay.
    /// @return actionId Queued batch identifier.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

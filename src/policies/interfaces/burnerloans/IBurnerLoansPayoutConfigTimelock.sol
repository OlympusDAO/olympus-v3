// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @notice Delayed routing and recovery for one concrete Burner Loans Payout.
/// @dev Proposals accept ADMIN or Burner Loans admin. Distributor replacement is a direct ADMIN call on Payout.
interface IBurnerLoansPayoutConfigTimelock {
    /// @notice The target is incompatible or reports a different Kernel.
    /// @param payout Invalid custody address.
    error BurnerLoansPayoutTimelock_InvalidPayout(address payout);

    /// @notice This timelock is not the target's selected local controller.
    error BurnerLoansPayoutTimelock_NotController();

    /// @notice Target reverted without safely propagatable bounded data.
    /// @param selector Failed Payout operation.
    error BurnerLoansPayoutTimelock_SubActionCallFailed(bytes4 selector);

    /// @notice Returns the immutable target; it does not follow Core replacements.
    /// @return target Payout receiving delayed calls.
    function payout() external view returns (IBurnerLoansPayout target);

    /// @notice Queues the fee routing flag.
    /// @param enabled Whether fees route to RevenueDistributor.
    /// @return actionId Queued operation identifier.
    function queueSetSendFeesToDistributor(bool enabled) external returns (uint64 actionId);

    /// @notice Queues the independent yield routing flag.
    /// @param enabled Whether DepositManager yield routes directly to RevenueDistributor.
    /// @return actionId Queued operation identifier.
    function queueSetSendYieldToDistributor(bool enabled) external returns (uint64 actionId);

    /// @notice Queues recovery of the live unreserved token balance.
    /// @param token ERC-20 token held by this Payout.
    /// @param destination Recipient of recovered surplus.
    /// @return actionId Queued operation identifier.
    function queueRescue(address token, address destination) external returns (uint64 actionId);

    /// @notice Queues redirection of a live pending entitlement.
    /// @param token Token owed to the recipient.
    /// @param recipient Current entitlement owner or role recipient.
    /// @param destination Recovery destination.
    /// @param amount Exact positive amount to recover.
    /// @return actionId Queued operation identifier.
    function queueRescuePendingPayout(
        address token,
        address recipient,
        address destination,
        uint256 amount
    ) external returns (uint64 actionId);

    /// @notice Queues an ordered batch of admitted Payout operations for atomic execution.
    /// @param actions_ Supported Payout operations in execution order.
    /// @return actionId Queued batch identifier.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

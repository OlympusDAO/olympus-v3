// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @notice Delayed referral and price-cache age settings for an immutable Risk policy.
interface IBurnerLoansRiskConfigTimelock {
    /// @notice Required Risk metadata is incompatible or malformed.
    /// @param risk Invalid target.
    error BurnerLoansRiskTimelock_InvalidRisk(address risk);
    /// @notice The queue is not Risk's selected configuration operator.
    error BurnerLoansRiskTimelock_NotController();
    /// @notice A failed dispatch did not supply safely propagatable bounded revert data.
    /// @param selector Failed Risk setter.
    error BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector);

    /// @notice Returns the immutable target.
    /// @return target Risk receiving delayed setting changes.
    function risk() external view returns (IBurnerLoansRisk target);

    /// @notice Queues the share of upfront fees allocated to approved referrals.
    /// @param bps Share in basis points; 10,000 equals 100%.
    /// @return actionId Queued intent identifier.
    function queueSetReferralFeeBps(uint16 bps) external returns (uint64 actionId);

    /// @notice Queues eligibility for one nonzero referrer.
    /// @param referrer Referral recipient.
    /// @param allowed Whether future operations may name this referrer.
    /// @return actionId Queued intent identifier.
    function queueSetReferrerAllowed(
        address referrer,
        bool allowed
    ) external returns (uint64 actionId);

    /// @notice Queues the maximum accepted cached-price age.
    /// @param age Cache age in seconds; zero is supported.
    /// @return actionId Queued intent identifier.
    function queueSetPriceCacheMaxAge(uint48 age) external returns (uint64 actionId);

    /// @notice Queues supported setting changes for atomic execution.
    /// @param actions Ordered Risk setter instructions.
    /// @return actionId Queued batch identifier.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions
    ) external returns (uint64 actionId);
}

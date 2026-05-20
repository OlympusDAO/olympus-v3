// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title ILZBridgeAndDelegateConfig
/// @notice Timelock policy that owns LayerZero bridge configuration on behalf of the
///         LZBridgeGateway, LZEndpointDelegate, and periphery LZCrossChainBridge contracts.
/// @dev The policy is intended to hold the `bridge_configurator` role on the
///      gateway/delegate and to be pinned as `configurator` on the periphery bridge. In
///      that deployment shape every `bridge_configurator`-gated mutator on the gateway
///      and the delegate, and every `configurator`-gated setter on the periphery, is
///      reached only through the queue exposed here; the contracts themselves only
///      enforce the role / configurator gate. Gateway, delegate, and facilitator
///      mutators are submitted as sub-actions of `queue`; the policy's own configuration
///      (target slots, timelock delay) is managed through the typed `queueSetTarget*` and
///      `queueSetTimelockDelay` helpers. Proposer roles map back to the existing
///      `bridge_admin`, `bridge_rate_limiter`, and `admin` roles; emergency cancels
///      malicious or stale queued actions.
///
///      Implementations are expected to inherit `TimelockBatchQueue` and extend its event
///      and error surface; the inherited interface is exposed by also implementing
///      `ITimelockBatchQueue`.
interface ILZBridgeAndDelegateConfig is ITimelockBatchQueue {
    // ========== TYPES ========== //

    /// @notice Which target slot a queued sub-action was validated against at queue time.
    /// @dev `NONE` is the zero value, meaning "no sub-action recorded".
    enum TargetKind {
        NONE,
        GATEWAY,
        DELEGATE,
        FACILITATOR,
        SELF
    }

    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument or proposed target slot is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZBridgeAndDelegateConfig_InvalidAddress(string parameter);

    /// @notice Thrown at execution when the target slot for a sub-action's queue-time
    ///         `TargetKind` no longer holds the address the action was queued against (the
    ///         slot was rotated between queue and execution). The action can be cleared via
    ///         emergency cancellation and re-queued against the new target.
    /// @param actionId The queued action ID.
    /// @param index The sub-action position within the batch.
    /// @param queuedTarget The address the sub-action was validated against at queue time.
    /// @param currentTarget The address the slot currently holds.
    error LZBridgeAndDelegateConfig_SubActionTargetStale(
        uint64 actionId,
        uint256 index,
        address queuedTarget,
        address currentTarget
    );

    // ========== EVENTS ========== //

    /// @notice Emitted when the gateway target slot is updated through the timelock queue.
    /// @param gateway The new gateway address.
    event TargetGatewaySet(address indexed gateway);

    /// @notice Emitted when the delegate target slot is updated through the timelock queue.
    /// @param delegate The new delegate address.
    event TargetDelegateSet(address indexed delegate);

    /// @notice Emitted when the facilitator target slot is updated through the timelock queue.
    /// @param facilitator The new facilitator address.
    event TargetFacilitatorSet(address indexed facilitator);

    // ========== VIEW ========== //

    /// @notice The LZBridgeGateway this policy manages.
    function gateway() external view returns (address);

    /// @notice The LZEndpointDelegate this policy manages.
    function delegate() external view returns (address);

    /// @notice The periphery LZCrossChainBridge this policy manages.
    function facilitator() external view returns (address);

    /// @notice Minimum accepted timelock delay.
    // solhint-disable-next-line func-name-mixedcase
    function MIN_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Maximum accepted timelock delay.
    // solhint-disable-next-line func-name-mixedcase
    function MAX_TIMELOCK_DELAY() external view returns (uint48);

    /// @notice Length of the window after `executableAt` during which a queued action may be
    ///         executed before it expires.
    // solhint-disable-next-line func-name-mixedcase
    function EXECUTION_WINDOW() external view returns (uint48);

    // ========== QUEUE: SELF ========== //

    /// @notice Queues a self-call updating the policy's `gateway` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newGateway_ The new gateway address.
    /// @return actionId The queued action ID.
    function queueSetTargetGateway(address newGateway_) external returns (uint64 actionId);

    /// @notice Queues a self-call updating the policy's `delegate` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newDelegate_ The new delegate address.
    /// @return actionId The queued action ID.
    function queueSetTargetDelegate(address newDelegate_) external returns (uint64 actionId);

    /// @notice Queues a self-call updating the policy's `facilitator` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newFacilitator_ The new facilitator address.
    /// @return actionId The queued action ID.
    function queueSetTargetFacilitator(address newFacilitator_) external returns (uint64 actionId);

    /// @notice Queues a self-call updating the configured timelock delay.
    /// @dev Proposer access: `admin` only.
    /// @param delay_ The new timelock delay in seconds.
    /// @return actionId The queued action ID.
    function queueSetTimelockDelay(uint48 delay_) external returns (uint64 actionId);

    // ========== QUEUE: BATCH ========== //

    /// @notice Queues a batch of one or more gateway, delegate, or facilitator sub-actions
    ///         for atomic timelocked execution.
    /// @dev Each sub-action is validated as if it had been submitted individually; the
    ///      caller must hold the proposer role required by every sub-action in the batch.
    ///      Self-targeted sub-actions are rejected: the policy's own configuration is
    ///      managed only through the typed `queueSetTarget*` / `queueSetTimelockDelay`
    ///      helpers.
    /// @param actions_ The sub-actions to queue.
    /// @return actionId The queued action ID.
    function queue(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId);
}

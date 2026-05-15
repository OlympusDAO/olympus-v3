// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";

import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {ITimelockBatchQueue} from "src/policies/interfaces/utils/ITimelockBatchQueue.sol";

/// @title ILZBridgeAndDelegateConfig
/// @notice Timelock policy that owns LayerZero bridge configuration on behalf of the
///         LZBridgeGateway, LZEndpointDelegate, and periphery LZCrossChainBridge contracts.
/// @dev The policy is intended to hold the `bridge_configurator` role on the
///      gateway/delegate and to be pinned as `configurator` on the periphery bridge. In
///      that deployment shape every `bridge_configurator`-gated mutator on the gateway
///      and the delegate, and every `configurator`-gated setter on the periphery, is
///      reached only through the queue exposed here; the contracts themselves only
///      enforce the role / configurator gate. Proposer roles on the queue helpers map
///      back to the existing `bridge_admin`, `bridge_rate_limiter`, and `admin` roles;
///      emergency cancels malicious or stale queued actions.
///
///      Implementations are expected to inherit `TimelockBatchQueue` and extend its event
///      and error surface; the inherited interface is exposed by also implementing
///      `ITimelockBatchQueue`.
interface ILZBridgeAndDelegateConfig is ITimelockBatchQueue {
    // ========== ERRORS ========== //

    /// @notice Thrown when a constructor argument or proposed target slot is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZBridgeAndDelegateConfig_InvalidAddress(string parameter);

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

    // ========== QUEUE: GATEWAY ========== //

    /// @notice Queues a `gateway.setDelegate` call (LZ-OApp endpoint delegate assignment).
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param delegate_ The new LZ endpoint delegate address.
    /// @return actionId_ The queued action ID.
    function queueSetEndpointDelegate(address delegate_) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.increaseBridgedSupply` call.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param amount_ The amount to increase the bridged supply by.
    /// @return actionId_ The queued action ID.
    function queueIncreaseBridgedSupply(uint256 amount_) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.decreaseBridgedSupply` call.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param amount_ The amount to decrease the bridged supply by.
    /// @return actionId_ The queued action ID.
    function queueDecreaseBridgedSupply(uint256 amount_) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.setOutRateLimits` call.
    /// @dev Proposer access: `bridge_rate_limiter`, `bridge_admin`, or `admin`.
    /// @param configs_ The outbound rate limit configurations to apply.
    /// @return actionId_ The queued action ID.
    function queueSetOutRateLimits(
        IOffsettingRateLimiter.RateLimitConfig[] calldata configs_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.setInRateLimits` call.
    /// @dev Proposer access: `bridge_rate_limiter`, `bridge_admin`, or `admin`.
    /// @param configs_ The inbound rate limit configurations to apply.
    /// @return actionId_ The queued action ID.
    function queueSetInRateLimits(
        IOffsettingRateLimiter.RateLimitConfig[] calldata configs_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.clearOutboundInFlight` call.
    /// @dev Proposer access: `bridge_rate_limiter`, `bridge_admin`, or `admin`.
    /// @param eids_ The endpoint identifiers whose outbound in-flight amount to clear.
    /// @return actionId_ The queued action ID.
    function queueClearOutboundInFlight(
        uint32[] calldata eids_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.clearInboundInFlight` call.
    /// @dev Proposer access: `bridge_rate_limiter`, `bridge_admin`, or `admin`.
    /// @param eids_ The endpoint identifiers whose inbound in-flight amount to clear.
    /// @return actionId_ The queued action ID.
    function queueClearInboundInFlight(uint32[] calldata eids_) external returns (uint64 actionId_);

    /// @notice Queues a `gateway.setGracePeriod` call.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param period_ The new grace window length in seconds.
    /// @return actionId_ The queued action ID.
    function queueSetGatewayGracePeriod(uint32 period_) external returns (uint64 actionId_);

    // ========== QUEUE: DELEGATE ========== //

    /// @notice Queues a `delegate.setSendLibrary` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param eid_ The destination endpoint ID.
    /// @param lib_ The send library address to pin.
    /// @return actionId_ The queued action ID.
    function queueSetSendLibrary(uint32 eid_, address lib_) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.setReceiveLibrary` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param eid_ The source endpoint ID.
    /// @param lib_ The receive library address to pin.
    /// @param gracePeriod_ Grace period for the receive library migration.
    /// @return actionId_ The queued action ID.
    function queueSetReceiveLibrary(
        uint32 eid_,
        address lib_,
        uint256 gracePeriod_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.setReceiveLibraryTimeout` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param eid_ The source endpoint ID.
    /// @param lib_ The receive library address.
    /// @param expiry_ The expiry timestamp for the previous receive library.
    /// @return actionId_ The queued action ID.
    function queueSetReceiveLibraryTimeout(
        uint32 eid_,
        address lib_,
        uint256 expiry_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.setEndpointConfig` call on a LayerZero message library.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param lib_ The message library address.
    /// @param params_ Array of ULN/Executor configuration parameters per EID.
    /// @return actionId_ The queued action ID.
    function queueSetEndpointConfig(
        address lib_,
        SetConfigParam[] calldata params_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.skip` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address.
    /// @param nonce_ The nonce to skip.
    /// @return actionId_ The queued action ID.
    function queueSkip(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.nilify` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address.
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The hash of the payload to nilify.
    /// @return actionId_ The queued action ID.
    function queueNilify(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.burn` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address.
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The hash of the payload to burn.
    /// @return actionId_ The queued action ID.
    function queueBurn(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external returns (uint64 actionId_);

    /// @notice Queues a `delegate.clear` call on the LayerZero endpoint.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param origin_ Origin of the inbound message.
    /// @param guid_ GUID of the inbound message.
    /// @param message_ Original message bytes.
    /// @return actionId_ The queued action ID.
    function queueClear(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_
    ) external returns (uint64 actionId_);

    // ========== QUEUE: FACILITATOR ========== //

    /// @notice Queues a `facilitator.setGateway` call on the periphery bridge.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param gateway_ The new gateway address.
    /// @return actionId_ The queued action ID.
    function queueSetFacilitatorGateway(address gateway_) external returns (uint64 actionId_);

    /// @notice Queues a `facilitator.setReEnabler` call on the periphery bridge.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param reEnabler_ The new re-enabler address, or `address(0)` to clear.
    /// @return actionId_ The queued action ID.
    function queueSetFacilitatorReEnabler(address reEnabler_) external returns (uint64 actionId_);

    /// @notice Queues a `facilitator.setGracePeriod` call on the periphery bridge.
    /// @dev Proposer access: `bridge_admin` or `admin`.
    /// @param period_ The new grace window length in seconds.
    /// @return actionId_ The queued action ID.
    function queueSetFacilitatorGracePeriod(uint32 period_) external returns (uint64 actionId_);

    /// @notice Queues a `facilitator.setConfigurator` call on the periphery bridge, which
    ///         rotates the periphery bridge to a new configurator policy.
    /// @dev Proposer access: `admin` only.
    /// @param newConfigurator_ The new configurator address.
    /// @return actionId_ The queued action ID.
    function queueSetFacilitatorConfigurator(
        address newConfigurator_
    ) external returns (uint64 actionId_);

    // ========== QUEUE: SELF ========== //

    /// @notice Queues a self-call updating the policy's `gateway` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newGateway_ The new gateway address.
    /// @return actionId_ The queued action ID.
    function queueSetTargetGateway(address newGateway_) external returns (uint64 actionId_);

    /// @notice Queues a self-call updating the policy's `delegate` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newDelegate_ The new delegate address.
    /// @return actionId_ The queued action ID.
    function queueSetTargetDelegate(address newDelegate_) external returns (uint64 actionId_);

    /// @notice Queues a self-call updating the policy's `facilitator` target slot.
    /// @dev Proposer access: `admin` only.
    /// @param newFacilitator_ The new facilitator address.
    /// @return actionId_ The queued action ID.
    function queueSetTargetFacilitator(address newFacilitator_) external returns (uint64 actionId_);

    /// @notice Queues a self-call updating the configured timelock delay.
    /// @dev Proposer access: `admin` only.
    /// @param delay_ The new timelock delay in seconds.
    /// @return actionId_ The queued action ID.
    function queueSetTimelockDelay(uint48 delay_) external returns (uint64 actionId_);

    // ========== QUEUE: BATCH ========== //

    /// @notice Queues an arbitrary batch of supported sub-actions for atomic execution.
    /// @dev Each sub-action is validated as if it had been submitted individually; the
    ///      strictest proposer role implied by the sub-actions in the batch applies.
    /// @param actions_ The sub-actions to queue.
    /// @return actionId_ The queued action ID.
    function queueBatch(
        ITimelockBatchQueue.BatchAction[] memory actions_
    ) external returns (uint64 actionId_);
}

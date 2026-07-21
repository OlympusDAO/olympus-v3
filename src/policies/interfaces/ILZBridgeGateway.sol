// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {MessagingFee, MessagingReceipt} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";

/// @title ILZBridgeGateway
/// @notice Interface for the LZ Bridge Gateway infrastructure policy (LayerZero V2).
/// @dev Handles LayerZero endpoint communication, OHM mint/burn via MINTR, peer management,
///      enforced options, bidirectional rate limiting, and bridged supply tracking.
interface ILZBridgeGateway is IOffsettingRateLimiter {
    // ========= ERRORS ========= //

    /// @notice Thrown when an address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZBridgeGateway_InvalidAddress(string parameter);

    /// @notice Thrown when msg.sender is not the LayerZero endpoint.
    error LZBridgeGateway_OnlyEndpoint();

    /// @notice Thrown when a message originates from a non-peer source.
    /// @param eid The source endpoint ID.
    /// @param sender The sender bytes32 address.
    error LZBridgeGateway_OnlyPeer(uint32 eid, bytes32 sender);

    /// @notice Thrown when no peer is configured for a destination endpoint.
    /// @param eid The endpoint ID.
    error LZBridgeGateway_NoPeer(uint32 eid);

    /// @notice Thrown when a received message has an unknown message type.
    /// @param msgType The unknown message type.
    error LZBridgeGateway_InvalidMessageType(uint8 msgType);

    /// @notice Thrown when a received message payload has an invalid length.
    error LZBridgeGateway_InvalidPayload();

    /// @notice Thrown when the bridged supply would underflow on receive.
    /// @param bridgedSupply The current bridged supply.
    /// @param amount The amount being received.
    error LZBridgeGateway_BridgedSupplyUnderflow(uint256 bridgedSupply, uint256 amount);

    /// @notice Thrown when a canonical-only function is called on a non-canonical chain.
    error LZBridgeGateway_NotCanonical();

    /// @notice Thrown when options are invalid (not Type 3 or malformed).
    /// @param options The invalid options bytes.
    error LZBridgeGateway_InvalidOptions(bytes options);

    /// @notice Thrown when lzReceive is called while receiving is disabled.
    error LZBridgeGateway_ReceiveNotEnabled();

    /// @notice Thrown when setIsReceiveEnabled is called with the current value.
    error LZBridgeGateway_ReceiveAlreadyInDesiredState();

    /// @notice Thrown when `initializeBridgedSupply` is called after it has already succeeded.
    error LZBridgeGateway_BridgedSupplyAlreadyInitialized();

    /// @notice Thrown when `initializeBridgedSupply` is called while `bridgedSupply` is non-zero.
    /// @param bridgedSupply The current bridged supply.
    error LZBridgeGateway_BridgedSupplyAlreadyNonZero(uint256 bridgedSupply);

    /// @notice Thrown when an amount argument is zero. Used by `initializeBridgedSupply`,
    ///         `increaseBridgedSupply`, and `decreaseBridgedSupply`.
    error LZBridgeGateway_ZeroAmount();

    // ========= EVENTS ========= //

    /// @notice Emitted when OHM is burned and sent to another chain.
    /// @param sender The address that initiated the send.
    /// @param amount The amount of OHM sent.
    /// @param dstEid The destination endpoint ID.
    /// @param guid The LayerZero message GUID.
    event Sent(address indexed sender, uint256 amount, uint32 indexed dstEid, bytes32 guid);

    /// @notice Emitted when OHM is received and minted from another chain.
    /// @param receiver The address that received the minted OHM.
    /// @param amount The amount of OHM minted.
    /// @param srcEid The LayerZero source endpoint ID.
    /// @param guid The LayerZero message GUID.
    event Received(address indexed receiver, uint256 amount, uint32 indexed srcEid, bytes32 guid);

    /// @notice Emitted when a peer is set for a destination endpoint.
    /// @param eid The endpoint ID.
    /// @param peer The peer address (bytes32).
    event PeerSet(uint32 eid, bytes32 peer);

    /// @notice Emitted when the delegate is set on the endpoint.
    /// @param delegate The new delegate address.
    event DelegateSet(address indexed delegate);

    /// @notice Emitted when the bridged supply is initialized via the one-shot bootstrap path.
    /// @param amount The initial bridged supply written to the gateway.
    event BridgedSupplyInitialized(uint256 amount);

    /// @notice Emitted when bridged supply is forcibly increased by an admin.
    /// @param amount The amount added.
    event BridgedSupplyForciblyIncreased(uint256 amount);

    /// @notice Emitted when bridged supply is forcibly decreased by an admin.
    /// @param amount The amount subtracted.
    event BridgedSupplyForciblyDecreased(uint256 amount);

    /// @notice Emitted when bridged supply increases (outbound transfer on canonical chain).
    /// @param amount The amount added.
    event BridgedSupplyIncreased(uint256 amount);

    /// @notice Emitted when bridged supply decreases (inbound transfer on canonical chain).
    /// @param amount The amount subtracted.
    event BridgedSupplyDecreased(uint256 amount);

    /// @notice Emitted when enforced options are set.
    /// @param enforcedOptions The enforced option parameters.
    event EnforcedOptionsSet(EnforcedOptionParam[] enforcedOptions);

    /// @notice Emitted when the isReceiveEnabled flag is changed.
    /// @param isReceiveEnabled The new value.
    event IsReceiveEnabledSet(bool isReceiveEnabled);

    // ========= CORE FUNCTIONS ========= //

    /// @notice Burns OHM held by the gateway and sends a bridge message to a destination chain.
    /// @dev Only callable by an address with the `bridge_facilitator` role. The caller must
    ///      transfer OHM to the gateway before calling this function. The gateway burns the OHM
    ///      via MINTR and sends a LayerZero V2 message.
    ///
    ///      On canonical chains, increments bridgedSupply.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to burn and send.
    /// @param refundAddress_ The address to receive excess native token refund.
    /// @param extraOptions_ Additional Type 3 options to combine with enforced options.
    /// @return receipt The LayerZero messaging receipt. `receipt.fee.nativeFee` is the
    ///         actual native amount charged by the endpoint (may be less than msg.value;
    ///         excess is refunded to `refundAddress_`).
    function burnAndSend(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata extraOptions_
    ) external payable returns (MessagingReceipt memory receipt);

    // ========= FEE ESTIMATION ========= //

    /// @notice Estimates the fee for sending OHM to a destination chain.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    /// @param extraOptions_ Additional Type 3 options to combine with enforced options.
    /// @return fee The estimated messaging fee (native + lzToken).
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata extraOptions_
    ) external view returns (MessagingFee memory fee);

    // ========= ADMIN FUNCTIONS ========= //

    /// @notice Sets the peer gateway address for a remote endpoint ID (destination).
    /// @dev Only callable by the admin role. Pass `bytes32(0)` to clear.
    ///
    /// @param eid_ The remote endpoint ID.
    /// @param peer_ The peer (remote gateway) address (bytes32 or `bytes32(0)` to clear).
    function setPeer(uint32 eid_, bytes32 peer_) external;

    /// @notice Sets whether the gateway can process inbound LayerZero messages.
    /// @dev Only callable by the emergency or admin role.
    ///
    /// @param isReceiveEnabled_ The desired state of the flag.
    function setIsReceiveEnabled(bool isReceiveEnabled_) external;

    /// @notice Sets the delegate on the LayerZero endpoint.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///
    ///      The delegate is authorized to configure anything on the LayerZero endpoint
    ///      on behalf of this contract (e.g. send/receive libraries, DVN config).
    ///      `delegate_` must be nonzero: the delegate cannot be cleared, only replaced
    ///      with another nonzero address.
    ///
    /// @param delegate_ The new delegate address; must be nonzero.
    function setDelegate(address delegate_) external;

    /// @notice One-shot bootstrap of the bridged supply on the canonical chain.
    /// @dev Only callable by the `bridge_admin` or `admin` role and only on canonical chains.
    ///
    /// @param amount_ The initial bridged supply to write.
    function initializeBridgedSupply(uint256 amount_) external;

    /// @notice Increases the bridged supply by the given amount and syncs the MINTR mint approval.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///      Only available on canonical chains.
    ///      Used for error-recovery (e.g. supply underflow caused by misrouted messages).
    ///      Delta-based to avoid race conditions with concurrent bridge messages.
    ///
    /// @param amount_ The amount to increase bridged supply by.
    function increaseBridgedSupply(uint256 amount_) external;

    /// @notice Decreases the bridged supply by the given amount and syncs the MINTR mint approval.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///      Only available on canonical chains.
    ///      Used for error-recovery (e.g. correcting supply after undeliverable messages).
    ///      Delta-based to avoid race conditions with concurrent bridge messages.
    ///
    /// @param amount_ The amount to decrease bridged supply by.
    function decreaseBridgedSupply(uint256 amount_) external;

    /// @notice Sets enforced options for specific endpoint and message type combinations.
    /// @dev Only callable by the admin role. Each option must be Type 3.
    ///
    /// @param enforcedOptions_ Array of enforced option parameters.
    function setEnforcedOptions(EnforcedOptionParam[] calldata enforcedOptions_) external;

    /// @notice Configures outbound rate limits for one or more destination endpoints.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///
    /// @param configs_ The outbound rate limit configurations to apply.
    function setOutRateLimits(RateLimitConfig[] calldata configs_) external;

    /// @notice Configures inbound rate limits for one or more source endpoints.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///
    /// @param configs_ The inbound rate limit configurations to apply.
    function setInRateLimits(RateLimitConfig[] calldata configs_) external;

    /// @notice Clears the outbound in-flight amount for one or more destination endpoints.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///
    /// @param eids_ The endpoint identifiers whose outbound in-flight amount should be cleared.
    function clearOutboundInFlight(uint32[] calldata eids_) external;

    /// @notice Clears the inbound in-flight amount for one or more source endpoints.
    /// @dev Only callable by the `bridge_configurator` role, which is expected to be
    ///      granted exclusively to `LZBridgeAndDelegateConfig` (the timelock policy).
    ///
    /// @param eids_ The endpoint identifiers whose inbound in-flight amount should be cleared.
    function clearInboundInFlight(uint32[] calldata eids_) external;

    // ========= VIEW FUNCTIONS ========= //

    /// @notice Validates the payload that would be passed to `setDelegate`.
    /// @dev Mirrors the input invariants enforced by `setDelegate` so that callers (for
    ///      instance, a timelock policy) can fail early at queue time rather than at
    ///      execution time.
    /// @param delegate_ The candidate delegate address.
    function validateSetDelegate(address delegate_) external pure;

    /// @notice Validates the payload that would be passed to `increaseBridgedSupply`.
    /// @dev Mirrors the input invariants enforced by `increaseBridgedSupply` so that
    ///      callers (for instance, a timelock policy) can fail early at queue time rather
    ///      than at execution time.
    /// @param amount_ The candidate increase amount.
    function validateIncreaseBridgedSupply(uint256 amount_) external view;

    /// @notice Validates the payload that would be passed to `decreaseBridgedSupply`.
    /// @dev Mirrors the input invariants enforced by `decreaseBridgedSupply` so that
    ///      callers (for instance, a timelock policy) can fail early at queue time rather
    ///      than at execution time.
    /// @param amount_ The candidate decrease amount.
    function validateDecreaseBridgedSupply(uint256 amount_) external view;

    /// @notice The LayerZero V2 endpoint address.
    // solhint-disable-next-line func-name-mixedcase
    function LZ_ENDPOINT() external view returns (address);

    /// @notice Returns the OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the current bridged supply (canonical only).
    function bridgedSupply() external view returns (uint256);

    /// @notice Returns whether the one-shot `initializeBridgedSupply` has already succeeded.
    function bridgedSupplyInitialized() external view returns (bool);

    /// @notice Returns the peer for a given endpoint ID.
    /// @param eid The remote endpoint ID.
    /// @return The peer address (as bytes32).
    function peers(uint32 eid) external view returns (bytes32);

    /// @notice Returns the enforced options for a given endpoint and message type.
    /// @param eid The endpoint ID.
    /// @param msgType The message type.
    /// @return The enforced options bytes.
    function enforcedOptions(uint32 eid, uint16 msgType) external view returns (bytes memory);

    /// @notice Combines enforced options with caller-provided extra options.
    /// @param eid_ The endpoint ID.
    /// @param msgType_ The message type.
    /// @param extraOptions_ Caller-provided options.
    /// @return The combined options bytes.
    function combineOptions(
        uint32 eid_,
        uint16 msgType_,
        bytes calldata extraOptions_
    ) external view returns (bytes memory);

    /// @notice Whether lzReceive() can process incoming messages.
    /// @dev Automatically set to true by enable() and false by disable().
    ///      Can be manually set via setIsReceiveEnabled() to allow receiving
    ///      while the gateway is otherwise disabled (e.g., during gateway replacements).
    function isReceiveEnabled() external view returns (bool);

    /// @notice Returns whether this is the canonical (mainnet) chain.
    // solhint-disable-next-line func-name-mixedcase
    function IS_CANONICAL() external view returns (bool);

    /// @notice Returns the message type identifier for OHM bridge transfers.
    // solhint-disable-next-line func-name-mixedcase
    function MSG_BRIDGE_OHM() external view returns (uint8);
}

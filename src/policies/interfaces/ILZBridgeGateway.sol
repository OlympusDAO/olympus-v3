// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";
import {RateLimiter} from "@lz-oapp-evm-0.4.1/oapp/utils/RateLimiter.sol";
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";

/// @title ILZBridgeGateway
/// @notice Interface for the LZ Bridge Gateway infrastructure policy (LayerZero V2).
/// @dev Handles LayerZero endpoint communication, OHM mint/burn via MINTR, peer management,
///      enforced options, rate limiting, and bridged supply cap enforcement.
interface ILZBridgeGateway is IVersioned, ILZEndpointV2Admin {
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

    /// @notice Thrown when the bridged supply would exceed the cap.
    /// @param newSupply The resulting supply after the operation.
    /// @param cap The current cap.
    error LZBridgeGateway_BridgedSupplyCapExceeded(uint256 newSupply, uint256 cap);

    /// @notice Thrown when the bridged supply would underflow on receive.
    /// @param bridgedSupply The current bridged supply.
    /// @param amount The amount being received.
    error LZBridgeGateway_BridgedSupplyUnderflow(uint256 bridgedSupply, uint256 amount);

    /// @notice Thrown when a canonical-only function is called on a non-canonical chain.
    error LZBridgeGateway_NotCanonical();

    /// @notice Thrown when options are invalid (not Type 3 or malformed).
    /// @param options The invalid options bytes.
    error LZBridgeGateway_InvalidOptions(bytes options);

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
    event DelegateSet(address delegate);

    /// @notice Emitted when the bridged supply is set.
    /// @param bridgedSupply The new bridged supply value.
    event BridgedSupplySet(uint256 bridgedSupply);

    /// @notice Emitted when bridged supply increases (outbound transfer on canonical chain).
    /// @param amount The amount added.
    event BridgedSupplyIncreased(uint256 amount);

    /// @notice Emitted when bridged supply decreases (inbound transfer on canonical chain).
    /// @param amount The amount subtracted.
    event BridgedSupplyDecreased(uint256 amount);

    /// @notice Emitted when the bridged supply cap is set.
    /// @param bridgedSupplyCap The new bridged supply cap.
    event BridgedSupplyCapSet(uint256 bridgedSupplyCap);

    /// @notice Emitted when enforced options are set.
    /// @param enforcedOptions The enforced option parameters.
    event EnforcedOptionsSet(EnforcedOptionParam[] enforcedOptions);

    // ========= CORE FUNCTIONS ========= //

    /// @notice Burns OHM held by the gateway and sends a bridge message to a destination chain.
    /// @dev Only callable by an address with the `bridge_facilitator` role. The caller must
    ///      transfer OHM to the gateway before calling this function. The gateway burns the OHM
    ///      via MINTR and sends a LayerZero V2 message.
    ///
    ///      On canonical chains, increments bridgedSupply and checks against bridgedSupplyCap.
    ///
    ///      Reverts if:
    ///      - The caller does not have the `bridge_facilitator` role.
    ///      - The gateway is not enabled.
    ///      - No peer exists for the destination endpoint ID.
    ///      - The bridged supply cap would be exceeded (canonical only).
    ///      - The rate limit would be exceeded.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to burn and send.
    /// @param refundAddress_ The address to receive excess native token refund.
    /// @param extraOptions_ Additional Type 3 options to combine with enforced options.
    function burnAndSend(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata extraOptions_
    ) external payable;

    // ========= FEE ESTIMATION ========= //

    /// @notice Estimates the fee for sending OHM to a destination chain.
    ///
    ///         Reverts if:
    ///         - The recipient address is zero.
    ///         - No peer exists for the destination endpoint ID.
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

    /// @notice Sets the delegate on the LayerZero endpoint.
    /// @dev Only callable by the bridge_admin role.
    ///
    ///      The delegate is authorized to configure anything on the LayerZero endpoint
    ///      on behalf of this contract (e.g. send/receive libraries, DVN config).
    ///      Pass `address(0)` to clear the delegate.
    ///
    /// @param delegate_ The new delegate address, or `address(0)` to clear.
    function setDelegate(address delegate_) external;

    /// @notice Manually sets the bridged supply value.
    /// @dev Only callable by the bridge_admin role. Only available on canonical chains.
    ///      Required during bridge migration: the bridged amount at deployment differs from
    ///      the amount at OCG proposal execution, so the MS sets this value after the old
    ///      bridge is disabled and before the new one is enabled. Also used to correct
    ///      bridgedSupply in error-recovery scenarios (e.g. misrouted messages).
    ///
    ///      Reverts if:
    ///      - The caller does not have the bridge_admin role.
    ///      - IS_CANONICAL is false.
    ///
    /// @param bridgedSupply_ The new bridged supply value.
    function setBridgedSupply(uint256 bridgedSupply_) external;

    /// @notice Sets the maximum permitted bridged supply.
    /// @dev Only callable by the admin role. Only available on canonical chains.
    ///      The cap may be set below the current `bridgedSupply` to prevent further
    ///      outbound bridging without affecting already-bridged tokens.
    ///
    ///      Reverts if:
    ///      - The caller does not have the admin role.
    ///      - IS_CANONICAL is false.
    ///
    /// @param bridgedSupplyCap_ The new bridged supply cap.
    function setBridgedSupplyCap(uint256 bridgedSupplyCap_) external;

    /// @notice Sets enforced options for specific endpoint and message type combinations.
    /// @dev Only callable by the admin role. Each option must be Type 3.
    ///
    /// @param enforcedOptions_ Array of enforced option parameters.
    function setEnforcedOptions(EnforcedOptionParam[] calldata enforcedOptions_) external;

    /// @notice Sets rate limits for destination endpoints.
    /// @dev Only callable by the admin role.
    ///
    /// @param rateLimitConfigs_ Array of rate limit configurations.
    function setRateLimits(RateLimiter.RateLimitConfig[] memory rateLimitConfigs_) external;

    /// @notice Resets rate limit state (amountInFlight) for the given endpoint IDs.
    /// @dev Only callable by the bridge_admin role. Does not modify limit or window.
    ///
    /// @param eids_ The endpoint IDs to reset.
    function resetRateLimits(uint32[] memory eids_) external;

    // ========= VIEW FUNCTIONS ========= //

    /// @notice The LayerZero V2 endpoint address.
    // solhint-disable-next-line func-name-mixedcase
    function LZ_ENDPOINT() external view returns (address);

    /// @notice Returns the OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the current bridged supply (canonical only).
    function bridgedSupply() external view returns (uint256);

    /// @notice Returns the bridged supply cap (canonical only).
    function bridgedSupplyCap() external view returns (uint256);

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

    /// @notice Returns whether this is the canonical (mainnet) chain.
    // solhint-disable-next-line func-name-mixedcase
    function IS_CANONICAL() external view returns (bool);

    /// @notice Returns the message type identifier for OHM bridge transfers.
    // solhint-disable-next-line func-name-mixedcase
    function MSG_BRIDGE_OHM() external view returns (uint8);
}

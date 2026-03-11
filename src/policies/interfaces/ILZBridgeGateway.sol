// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {Origin} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroEndpointV2.sol";

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title ILZBridgeGateway
/// @notice Interface for the LZ Bridge Gateway infrastructure policy.
/// @dev Handles LayerZero V2 endpoint communication, OHM mint/burn via MINTR, peer
///      management, and bridged supply cap enforcement.
interface ILZBridgeGateway is IVersioned {
    // ========= ERRORS ========= //

    /// @notice Thrown when an address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZBridgeGateway_InvalidAddress(string parameter);

    /// @notice Thrown when msg.sender is not the LayerZero endpoint.
    error LZBridgeGateway_InvalidCaller();

    /// @notice Thrown when msg.sender is not the facilitator.
    error LZBridgeGateway_OnlyFacilitator();

    /// @notice Thrown when a message source is not trusted.
    error LZBridgeGateway_InvalidMessageSource();

    /// @notice Thrown when the retry payload does not match the stored hash.
    error LZBridgeGateway_InvalidPayload();

    /// @notice Thrown when the destination chain has no peer configured.
    error LZBridgeGateway_DestinationNotTrusted();

    /// @notice Thrown when a received message has an unknown message type.
    /// @param msgType The unknown message type.
    error LZBridgeGateway_InvalidMessageType(uint8 msgType);

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

    // ========= EVENTS ========= //

    /// @notice Emitted when OHM is received and minted from another chain.
    /// @param receiver The address that received the minted OHM.
    /// @param amount The amount of OHM minted.
    /// @param srcEid The LayerZero source endpoint ID.
    event Received(address indexed receiver, uint256 amount, uint32 indexed srcEid);

    /// @notice Emitted when a peer is set for a remote endpoint ID.
    /// @param eid The remote endpoint ID.
    /// @param peer The peer address encoded as bytes32.
    event PeerSet(uint32 indexed eid, bytes32 peer);

    /// @notice Emitted when a message is cleared from the LZ endpoint.
    /// @param srcEid The source endpoint ID.
    /// @param sender The sender address (bytes32).
    /// @param nonce The nonce of the cleared message.
    event MessageCleared(uint32 indexed srcEid, bytes32 sender, uint64 nonce);

    /// @notice Emitted when a message is retried via the LZ endpoint.
    /// @param srcEid The source endpoint ID.
    /// @param sender The sender address (bytes32).
    /// @param nonce The nonce of the retried message.
    event MessageRetried(uint32 indexed srcEid, bytes32 sender, uint64 nonce);

    /// @notice Emitted when a message nonce is skipped on the LZ endpoint.
    /// @param srcEid The source endpoint ID.
    /// @param sender The sender address (bytes32).
    /// @param nonce The nonce that was skipped.
    event NonceSkipped(uint32 indexed srcEid, bytes32 sender, uint64 nonce);

    /// @notice Emitted when a message is nilified on the LZ endpoint.
    /// @param srcEid The source endpoint ID.
    /// @param sender The sender address (bytes32).
    /// @param nonce The nonce of the nilified message.
    event MessageNilified(uint32 indexed srcEid, bytes32 sender, uint64 nonce);

    /// @notice Emitted when a message is burned on the LZ endpoint.
    /// @param srcEid The source endpoint ID.
    /// @param sender The sender address (bytes32).
    /// @param nonce The nonce of the burned message.
    event MessageBurned(uint32 indexed srcEid, bytes32 sender, uint64 nonce);

    /// @notice Emitted when the facilitator is set.
    /// @param facilitator The new facilitator address.
    event FacilitatorSet(address facilitator);

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

    // ========= CORE FUNCTIONS ========= //

    /// @notice Burns OHM held by the gateway and sends a bridge message to a destination chain.
    /// @dev Only callable by the facilitator. The facilitator must transfer OHM to the gateway
    ///      before calling this function. The gateway burns the OHM via MINTR and sends a
    ///      LayerZero V2 message.
    ///
    ///      On canonical chains, increments bridgedSupply and checks against bridgedSupplyCap.
    ///
    ///      Reverts if:
    ///      - The caller is not the facilitator.
    ///      - The gateway is not enabled.
    ///      - No peer exists for the destination endpoint ID.
    ///      - The bridged supply cap would be exceeded (canonical only).
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to burn and send.
    /// @param refundAddress_ The address to receive excess native token refund.
    /// @param options_ LayerZero V2 message options for executor gas settings.
    function burnAndSend(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata options_
    ) external payable;

    // ========= FEE ESTIMATION ========= //

    /// @notice Estimates the fee for sending OHM to a destination chain.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    /// @param options_ LayerZero V2 message options.
    /// @return nativeFee The estimated native token fee.
    /// @return lzTokenFee The estimated LZ token fee (unused).
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_,
        bytes calldata options_
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);

    // ========= ADMIN FUNCTIONS ========= //

    /// @notice Sets the facilitator address.
    /// @dev Only callable by the admin role.
    ///
    ///      Reverts if:
    ///      - facilitator_ is the zero address.
    ///
    /// @param facilitator_ The new facilitator address.
    function setFacilitator(address facilitator_) external;

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

    /// @notice Sets the peer gateway address for a remote endpoint ID.
    /// @dev Only callable by the admin role.
    ///      Pass `address(0)` to clear the peer for the endpoint ID.
    ///
    /// @param eid_ The remote endpoint ID.
    /// @param peerAddress_ The remote gateway address (or `address(0)` to clear).
    function setPeer(uint32 eid_, address peerAddress_) external;

    /// @notice Clears (discards) a verified inbound message from the LZ V2 endpoint.
    /// @dev Only callable by the bridge_admin role. Used to skip processing of a
    ///      poisoned or stuck message that has already been verified.
    ///
    ///      On canonical chains, clearing an inbound bridge message means `bridgedSupply`
    ///      will not be decremented for the cleared transfer. Call `setBridgedSupply()`
    ///      afterward to correct the accounting.
    ///
    /// @param origin_ The origin of the message (srcEid, sender, nonce).
    /// @param guid_ The global unique identifier of the message.
    /// @param message_ The message payload.
    function lzClear(Origin calldata origin_, bytes32 guid_, bytes calldata message_) external;

    /// @notice Retries delivery of a failed inbound message via the LZ V2 endpoint.
    /// @dev Only callable by the bridge_admin role. Calls `endpoint.lzReceive()` to
    ///      re-deliver a message that was verified but failed during execution.
    ///
    /// @param origin_ The origin of the message (srcEid, sender, nonce).
    /// @param guid_ The global unique identifier of the message.
    /// @param message_ The message payload.
    /// @param extraData_ Extra data provided by the executor.
    function lzRetryReceive(
        Origin calldata origin_,
        bytes32 guid_,
        bytes calldata message_,
        bytes calldata extraData_
    ) external payable;

    /// @notice Skips the next expected inbound nonce on the LZ V2 endpoint.
    /// @dev Only callable by the bridge_admin role. Used to skip a message that
    ///      cannot be verified for some reason. The nonce must be the next expected nonce.
    ///
    ///      On canonical chains, skipping an inbound bridge message means `bridgedSupply`
    ///      will not be decremented for the skipped transfer. Call `setBridgedSupply()`
    ///      afterward to correct the accounting.
    ///
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce to skip (must be inboundNonce + 1).
    function lzSkip(uint32 srcEid_, bytes32 sender_, uint64 nonce_) external;

    /// @notice Nilifies a verified message, preventing execution until re-verified.
    /// @dev Only callable by the bridge_admin role. Marks the payload hash as
    ///      unexecutable while allowing future re-verification.
    ///
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The payload hash to nilify.
    function lzNilify(
        uint32 srcEid_,
        bytes32 sender_,
        uint64 nonce_,
        bytes32 payloadHash_
    ) external;

    /// @notice Permanently burns a message from the LZ V2 endpoint.
    /// @dev Only callable by the bridge_admin role. Makes the nonce permanently
    ///      unexecutable and un-verifiable. Only works for nonces <= lazyInboundNonce.
    ///
    ///      On canonical chains, burning an inbound bridge message means `bridgedSupply`
    ///      will not be decremented for the burned transfer. Call `setBridgedSupply()`
    ///      afterward to correct the accounting.
    ///
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The payload hash to burn.
    function lzBurn(uint32 srcEid_, bytes32 sender_, uint64 nonce_, bytes32 payloadHash_) external;

    /// @notice Sets the send library for a remote endpoint ID.
    /// @dev Only callable by the bridge_admin role.
    ///
    /// @param eid_ The remote endpoint ID.
    /// @param lib_ The send library address.
    function setSendLibrary(uint32 eid_, address lib_) external;

    /// @notice Sets the receive library for a remote endpoint ID.
    /// @dev Only callable by the bridge_admin role.
    ///
    /// @param eid_ The remote endpoint ID.
    /// @param lib_ The receive library address.
    /// @param gracePeriod_ The grace period for the library switch.
    function setReceiveLibrary(uint32 eid_, address lib_, uint256 gracePeriod_) external;

    /// @notice Sets LayerZero config via the V2 endpoint.
    /// @dev Only callable by the bridge_admin role. Calls endpoint.setConfig().
    ///
    /// @param lib_ The message library address to configure.
    /// @param params_ The encoded SetConfigParam array.
    function setLZConfig(address lib_, bytes calldata params_) external;

    // ========= VIEW FUNCTIONS ========= //

    /// @notice Returns the peer for a remote endpoint ID.
    /// @param eid_ The remote endpoint ID.
    /// @return The peer as bytes32.
    function peers(uint32 eid_) external view returns (bytes32);

    /// @notice Returns the OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the facilitator address.
    function facilitator() external view returns (address);

    /// @notice Returns the current bridged supply (canonical only).
    function bridgedSupply() external view returns (uint256);

    /// @notice Returns the bridged supply cap (canonical only).
    function bridgedSupplyCap() external view returns (uint256);

    /// @notice Returns the LayerZero V2 endpoint address.
    function LZ_ENDPOINT() external view returns (address);

    /// @notice Returns whether this is the canonical (mainnet) chain.
    function IS_CANONICAL() external view returns (bool);

    /// @notice Returns the message type identifier for OHM bridge transfers.
    function MSG_BRIDGE_OHM() external view returns (uint8);
}

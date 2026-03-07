// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IVersioned} from "../../interfaces/IVersioned.sol";

/// @title ILZBridgeGateway
/// @notice Interface for the LZ Bridge Gateway infrastructure policy.
/// @dev Handles LayerZero endpoint communication, OHM mint/burn via MINTR, trusted remote
///      management, and bridged supply cap enforcement. Routes incoming messages by type:
///      bridge (OHM) or governance.
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

    /// @notice Thrown when no stored failed message exists for the given parameters.
    error LZBridgeGateway_NoStoredMessage();

    /// @notice Thrown when the retry payload does not match the stored hash.
    error LZBridgeGateway_InvalidPayload();

    /// @notice Thrown when the destination chain has no trusted remote configured.
    error LZBridgeGateway_DestinationNotTrusted();

    /// @notice Thrown when the trusted remote path is empty.
    error LZBridgeGateway_NoTrustedPath();

    /// @notice Thrown when a trusted remote lookup returns uninitialized data.
    error LZBridgeGateway_TrustedRemoteUninitialized();

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
    /// @param srcChainId The LayerZero source chain ID.
    event BridgeReceived(address indexed receiver, uint256 amount, uint16 indexed srcChainId);

    /// @notice Emitted when an LZ message fails to process.
    /// @param srcChainId The source chain ID.
    /// @param srcAddress The source address.
    /// @param nonce The message nonce.
    /// @param payload The message payload.
    /// @param reason The revert reason.
    event MessageFailed(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes payload,
        bytes reason
    );

    /// @notice Emitted when a failed message is successfully retried.
    /// @param srcChainId The source chain ID.
    /// @param srcAddress The source address.
    /// @param nonce The message nonce.
    /// @param payloadHash The hash of the retried payload.
    event RetryMessageSuccess(
        uint16 srcChainId,
        bytes srcAddress,
        uint64 nonce,
        bytes32 payloadHash
    );

    /// @notice Emitted when the precrime address is set.
    /// @param precrime The new precrime address.
    event PrecrimeSet(address precrime);

    /// @notice Emitted when a trusted remote path is set.
    /// @param remoteChainId The remote chain ID.
    /// @param path The stored trusted remote path.
    event TrustedRemoteSet(uint16 remoteChainId, bytes path);

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
    ///      LayerZero message.
    ///
    ///      On canonical chains, increments bridgedSupply and checks against bridgedSupplyCap.
    ///
    ///      Reverts if:
    ///      - The caller is not the facilitator.
    ///      - The gateway is not enabled.
    ///      - No trusted remote exists for the destination chain.
    ///      - The bridged supply cap would be exceeded (canonical only).
    ///
    /// @param dstChainId_ The LayerZero destination chain ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to burn and send.
    /// @param refundAddress_ The address to receive excess native token refund.
    /// @param adapterParams_ LayerZero adapter parameters for custom gas and airdrop settings.
    function burnAndSend(
        uint16 dstChainId_,
        address to_,
        uint256 amount_,
        address payable refundAddress_,
        bytes calldata adapterParams_
    ) external payable;

    /// @notice Retries a previously failed message.
    /// @dev Validates that the gateway is enabled and that the source is still a trusted remote.
    ///      This is a security fix over the original CrossChainBridge: retry re-validates
    ///      the trusted remote to prevent bypassing removed trusted remotes.
    ///
    ///      Reverts if:
    ///      - The gateway is not enabled.
    ///      - The trusted remote has been removed since the original failure.
    ///      - No stored failed message exists.
    ///      - The payload hash does not match the stored hash.
    ///
    /// @param srcChainId_ The source chain ID.
    /// @param srcAddress_ The source address.
    /// @param nonce_ The message nonce.
    /// @param payload_ The original message payload.
    function retryMessage(
        uint16 srcChainId_,
        bytes calldata srcAddress_,
        uint64 nonce_,
        bytes calldata payload_
    ) external;

    /// @notice Receives and routes an LZ message after validation.
    /// @dev Called via low-level self-call from lzReceive for error isolation.
    ///
    ///      Reverts if:
    ///      - The caller is not address(this).
    ///      - The message type is unknown.
    ///
    /// @param srcChainId_ The source chain ID.
    /// @param srcAddress_ The source address (unused).
    /// @param nonce_ The message nonce (unused).
    /// @param payload_ The message payload containing (uint8 msgType, bytes data).
    function receiveMessage(
        uint16 srcChainId_,
        bytes memory srcAddress_,
        uint64 nonce_,
        bytes memory payload_
    ) external;

    // ========= FEE ESTIMATION ========= //

    /// @notice Estimates the fee for sending OHM to a destination chain.
    ///
    /// @param dstChainId_ The LayerZero destination chain ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    /// @param adapterParams_ LayerZero adapter parameters.
    /// @return nativeFee The estimated native token fee.
    /// @return zroFee The estimated ZRO token fee (unused).
    function estimateSendFee(
        uint16 dstChainId_,
        address to_,
        uint256 amount_,
        bytes calldata adapterParams_
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    // ========= ADMIN FUNCTIONS ========= //

    /// @notice Sets the facilitator address.
    /// @dev Only callable by the admin role.
    ///
    /// @param facilitator_ The new facilitator address.
    function setFacilitator(address facilitator_) external;

    /// @notice Manually sets the bridged supply value.
    /// @dev Only callable by the admin role. Only available on canonical chains.
    ///      Required during migration to set the initial value.
    ///
    ///      Reverts if:
    ///      - The caller does not have the admin role.
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

    /// @notice Sets the trusted remote gateway address for a chain.
    /// @dev Only callable by the admin role. Stores the path as
    ///      `abi.encodePacked(remoteAddress_, address(this))`.
    ///      Pass `address(0)` to clear the trusted remote for the chain.
    ///
    /// @param remoteChainId_ The remote chain ID.
    /// @param remoteAddress_ The remote gateway address (or `address(0)` to clear).
    function setTrustedRemote(uint16 remoteChainId_, address remoteAddress_) external;

    /// @notice Sets the precrime address.
    /// @dev Only callable by the admin role.
    ///
    /// @param precrime_ The new precrime address.
    function setPrecrime(address precrime_) external;

    // ========= OTHER VIEW FUNCTIONS ========= //

    /// @notice Gets the LayerZero endpoint configuration for this contract.
    ///
    /// @param version_ The messaging library version.
    /// @param chainId_ The chain ID.
    /// @param userApplication_ The user application address (unused, queries self).
    /// @param configType_ The configuration type.
    /// @return config The configuration bytes.
    function getConfig(
        uint16 version_,
        uint16 chainId_,
        address userApplication_,
        uint256 configType_
    ) external view returns (bytes memory config);

    /// @notice Gets the trusted remote address for a given chain.
    /// @dev Extracts the remote address from the stored path
    ///      (`abi.encodePacked(remoteAddress, localAddress)`).
    ///      Reverts if no trusted remote is set for the chain.
    ///
    /// @param remoteChainId_ The remote chain ID.
    /// @return remoteAddress The trusted remote address.
    function getTrustedRemoteAddress(
        uint16 remoteChainId_
    ) external view returns (address remoteAddress);

    /// @notice Checks if a source address is a trusted remote for the given chain.
    /// @dev Reverts if either the source address or trusted remote is uninitialized.
    ///
    /// @param srcChainId_ The source chain ID.
    /// @param srcAddress_ The source address to check.
    /// @return isTrusted True if the address is a trusted remote.
    function isTrustedRemote(
        uint16 srcChainId_,
        bytes calldata srcAddress_
    ) external view returns (bool isTrusted);

    /// @notice Returns the hash of a failed message, or bytes32(0) if none.
    ///
    /// @param srcChainId_ The source chain ID.
    /// @param srcAddress_ The source address.
    /// @param nonce_ The message nonce.
    /// @return payloadHash The hash of the failed payload.
    function failedMessages(
        uint16 srcChainId_,
        bytes memory srcAddress_,
        uint64 nonce_
    ) external view returns (bytes32 payloadHash);

    /// @notice Returns the OHM token address.
    function ohm() external view returns (address);

    /// @notice Returns the facilitator address.
    function facilitator() external view returns (address);

    /// @notice Returns the current bridged supply (canonical only).
    function bridgedSupply() external view returns (uint256);

    /// @notice Returns the bridged supply cap (canonical only).
    function bridgedSupplyCap() external view returns (uint256);

    /// @notice Returns the trusted remote path for a given chain.
    function trustedRemoteLookup(uint16 chainId) external view returns (bytes memory);

    /// @notice Returns the precrime address.
    function precrime() external view returns (address);

    /// @notice Returns the LayerZero endpoint address.
    function LZ_ENDPOINT() external view returns (address);

    /// @notice Returns whether this is the canonical (mainnet) chain.
    function IS_CANONICAL() external view returns (bool);

    /// @notice Returns the message type identifier for OHM bridge transfers.
    function MSG_BRIDGE_OHM() external view returns (uint8);
}

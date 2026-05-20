// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

/// @title ILZCrossChainBridge
/// @notice Interface for the LZ Cross-Chain Bridge facilitator, the user-facing entry point
///         for sending OHM to other chains via LayerZero V2.
/// @dev It is a periphery contract, as it does not require any privileged access to the
///      Olympus protocol. It transfers OHM from the user to the gateway, which handles
///      burning and sending.
interface ILZCrossChainBridge {
    /// @notice Thrown when an address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZCrossChainBridge_InvalidAddress(string parameter);

    /// @notice Thrown when the send amount is zero.
    error LZCrossChainBridge_InsufficientAmount();

    /// @notice Thrown when `setConfigurator` is supplied a contract that does not implement the
    ///         `ILZBridgeAndDelegateConfig` interface via ERC-165.
    /// @param newConfigurator The unsupported new configurator address.
    error LZCrossChainBridge_InvalidConfigurator(address newConfigurator);

    /// @notice Emitted when OHM is sent to another chain.
    /// @param sender The address that initiated the bridge transfer.
    /// @param amount The amount of OHM bridged.
    /// @param dstEid The LayerZero destination endpoint ID.
    /// @param nativeFee The native token fee actually charged by LayerZero, read from
    ///        `MessagingReceipt`. May be less than `msgValue` when the caller overpays;
    ///        the excess is refunded to the sender by the LayerZero endpoint.
    /// @param msgValue The native value the caller supplied with the transaction.
    event Bridged(
        address indexed sender,
        uint256 amount,
        uint32 indexed dstEid,
        uint256 nativeFee,
        uint256 msgValue
    );

    /// @notice Emitted when the gateway address is updated.
    /// @param gateway The new gateway address.
    event GatewaySet(address indexed gateway);

    /// @notice Emitted when the re-enabler address is updated.
    /// @dev Setting the re-enabler to the zero address effectively disables the
    ///      `reEnable()` entry point until a non-zero address is configured again.
    /// @param reEnabler The new re-enabler address, or `address(0)` to clear.
    event ReEnablerSet(address indexed reEnabler);

    /// @notice Emitted when the configurator address is updated.
    /// @param configurator The new configurator address.
    event ConfiguratorSet(address indexed configurator);

    /// @notice Sends OHM to a destination chain via the gateway.
    /// @dev The user must approve this contract for the OHM amount before calling.
    ///      OHM is transferred from the user to the gateway, then the gateway burns and
    ///      sends via LayerZero. The caller must send the native token with the call to
    ///      cover the LayerZero messaging fee; excess is refunded to msg.sender.
    ///      Use estimateSendFee() to determine the required fee.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    function sendOhm(uint32 dstEid_, address to_, uint256 amount_) external payable;

    /// @notice Sets the gateway address.
    /// @dev Only callable by the address pinned in `configurator`, which is expected to be
    ///      an `LZBridgeAndDelegateConfig` instance (the timelock policy).
    ///
    /// @param gateway_ The new gateway address.
    function setGateway(address gateway_) external;

    /// @notice Sets the address authorized to call `reEnable()`.
    /// @dev Only callable by the address pinned in `configurator`, which is expected to be
    ///      an `LZBridgeAndDelegateConfig` instance (the timelock policy). The zero address
    ///      is permitted and effectively disables the `reEnable()` entry point until a
    ///      non-zero address is set.
    /// @param reEnabler_ The new re-enabler address, or `address(0)` to clear.
    function setReEnabler(address reEnabler_) external;

    /// @notice Sets the configurator address.
    /// @dev Bootstrap: when `configurator` is the zero address, only the owner may set the
    ///      first non-zero configurator. After bootstrap, rotation is only allowed by the
    ///      current configurator. The configurator is expected to be an
    ///      `LZBridgeAndDelegateConfig` instance (the timelock policy).
    ///
    ///      In both cases the new configurator must implement `ILZBridgeAndDelegateConfig`
    ///      via ERC-165 to prevent the bridge from being bricked by an incompatible address.
    /// @param newConfigurator_ The new configurator address.
    function setConfigurator(address newConfigurator_) external;

    /// @notice Validates the payload that would be passed to `setGateway`.
    /// @dev Mirrors the input invariants enforced by `setGateway` so that callers (for
    ///      instance, a timelock policy) can fail early at queue time rather than at
    ///      execution time.
    /// @param gateway_ The candidate gateway address.
    function validateSetGateway(address gateway_) external pure;

    /// @notice Validates the payload that would be passed to `setConfigurator`.
    /// @dev Mirrors the payload invariants enforced by `setConfigurator`: the zero-address
    ///      check and the ERC-165 `ILZBridgeAndDelegateConfig` guard.
    /// @param newConfigurator_ The candidate configurator address.
    function validateSetConfigurator(address newConfigurator_) external view;

    /// @notice Returns the LZBridgeGateway address.
    function gateway() external view returns (address);

    /// @notice Returns the address authorized to call `reEnable()`.
    /// @dev Returns `address(0)` when no re-enabler has been configured.
    function reEnabler() external view returns (address);

    /// @notice Returns the configurator address (an `LZBridgeAndDelegateConfig` instance).
    /// @dev Returns `address(0)` before the owner has performed the bootstrap call.
    function configurator() external view returns (address);

    /// @notice Returns the OHM token address.
    // solhint-disable-next-line func-name-mixedcase
    function OHM() external view returns (address);

    /// @notice Estimates the fee for sending OHM to a destination chain.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    /// @return fee The estimated messaging fee (native + lzToken (unused)).
    function estimateSendFee(
        uint32 dstEid_,
        address to_,
        uint256 amount_
    ) external view returns (MessagingFee memory fee);

    /// @notice Returns the current outbound capacity for a destination endpoint, with the
    ///         in-flight amount decayed against the current timestamp.
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @return inFlight The decayed outbound in-flight amount at the current timestamp.
    /// @return available The amount that may still be sent to the destination before the
    ///         outbound rate limit is exceeded.
    function sendable(uint32 dstEid_) external view returns (uint256 inFlight, uint256 available);

    /// @notice Returns the current inbound capacity for a source endpoint, with the
    ///         in-flight amount decayed against the current timestamp.
    ///
    /// @param srcEid_ The LayerZero source endpoint ID.
    /// @return inFlight The decayed inbound in-flight amount at the current timestamp.
    /// @return available The amount that may still be received from the source before
    ///         the inbound rate limit is exceeded.
    function receivable(uint32 srcEid_) external view returns (uint256 inFlight, uint256 available);
}

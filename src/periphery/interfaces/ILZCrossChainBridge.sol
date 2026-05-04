// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IVersioned} from "../../interfaces/IVersioned.sol";
import {MessagingFee} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

/// @title ILZCrossChainBridge
/// @notice Interface for the LZ Cross-Chain Bridge facilitator, the user-facing entry point
///         for sending OHM to other chains via LayerZero V2.
/// @dev It is a periphery contract, as it does not require any privileged access to the
///      Olympus protocol. It transfers OHM from the user to the gateway, which handles
///      burning and sending.
interface ILZCrossChainBridge is IVersioned {
    /// @notice Thrown when an address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZCrossChainBridge_InvalidAddress(string parameter);

    /// @notice Thrown when the send amount is zero.
    error LZCrossChainBridge_InsufficientAmount();

    /// @notice Emitted when OHM is sent to another chain.
    /// @param sender The address that initiated the bridge transfer.
    /// @param amount The amount of OHM bridged.
    /// @param dstEid The LayerZero destination endpoint ID.
    /// @param fees The native token fee paid for the bridge transfer.
    event Bridged(address indexed sender, uint256 amount, uint32 indexed dstEid, uint256 fees);

    /// @notice Emitted when the gateway address is updated.
    /// @param gateway The new gateway address.
    event GatewaySet(address gateway);

    /// @notice Sends OHM to a destination chain via the gateway.
    /// @dev The user must approve this contract for the OHM amount before calling.
    ///      OHM is transferred from the user to the gateway, then the gateway burns and
    ///      sends via LayerZero. The caller must send native token (ETH) with the call to
    ///      cover the LayerZero messaging fee; excess is refunded to msg.sender.
    ///      Use estimateSendFee() to determine the required fee.
    ///
    ///      Reverts if:
    ///      - The bridge is not enabled.
    ///      - amount_ is zero.
    ///      - The user has insufficient OHM balance or approval.
    ///      - The gateway reverts (e.g. no peer configured, rate limit exceeded, gateway not enabled).
    ///
    /// @param dstEid_ The LayerZero destination endpoint ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    function sendOhm(uint32 dstEid_, address to_, uint256 amount_) external payable;

    /// @notice Sets the gateway address.
    /// @dev Only callable by the owner.
    ///
    ///      Reverts if:
    ///      - The caller is not the owner.
    ///      - gateway_ is the zero address.
    ///
    /// @param gateway_ The new gateway address.
    function setGateway(address gateway_) external;

    /// @notice Returns the LZBridgeGateway address.
    function gateway() external view returns (address);

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

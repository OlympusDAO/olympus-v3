// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";

/// @title ILZCrossChainBridge
/// @notice Interface for the LZ Cross-Chain Bridge facilitator, the user-facing entry point
///         for sending OHM to other chains via LayerZero.
/// @dev It is a periphery contract, as it does not require any privileged access to the
///      Olympus protocol. It transfers OHM from the user to the gateway, which handles
///      burning and sending.
interface ILZCrossChainBridge is IEnabler, IVersioned {
    /// @notice Thrown when an address argument is the zero address.
    /// @param parameter The name of the invalid parameter.
    error LZCrossChainBridge_InvalidAddress(string parameter);

    /// @notice Thrown when the send amount is zero.
    error LZCrossChainBridge_InsufficientAmount();

    /// @notice Emitted when OHM is sent to another chain.
    /// @param sender The address that initiated the bridge transfer.
    /// @param amount The amount of OHM bridged.
    /// @param dstChainId The LayerZero destination chain ID.
    event Bridged(address indexed sender, uint256 amount, uint16 indexed dstChainId);

    /// @notice Emitted when the gateway address is updated.
    /// @param gateway The new gateway address.
    event GatewaySet(address gateway);

    /// @notice Sends OHM to a destination chain via the gateway.
    /// @dev The user must approve this contract for the OHM amount before calling.
    ///      OHM is transferred from the user to the gateway, then the gateway burns and
    ///      sends via LayerZero.
    ///
    ///      Reverts if:
    ///      - The bridge is not enabled.
    ///      - amount_ is zero.
    ///      - The user has insufficient OHM balance or approval.
    ///
    /// @param dstChainId_ The LayerZero destination chain ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    function sendOhm(uint16 dstChainId_, address to_, uint256 amount_) external payable;

    /// @notice Sets the gateway address.
    /// @dev Only callable by the owner.
    ///
    ///      Reverts if:
    ///      - gateway_ is the zero address.
    ///
    /// @param gateway_ The new gateway address.
    function setGateway(address gateway_) external;

    /// @notice Returns the LZBridgeGateway address.
    function gateway() external view returns (address);

    /// @notice Returns the OHM token address.
    function OHM() external view returns (address);

    /// @notice Estimates the fee for sending OHM to a destination chain.
    /// @dev Proxies to the gateway's estimateSendFee function with empty adapter params.
    ///
    /// @param dstChainId_ The LayerZero destination chain ID.
    /// @param to_ The recipient address on the destination chain.
    /// @param amount_ The amount of OHM to send.
    /// @return nativeFee The estimated native token fee.
    /// @return zroFee The estimated ZRO token fee (unused).
    function estimateSendFee(
        uint16 dstChainId_,
        address to_,
        uint256 amount_
    ) external view returns (uint256 nativeFee, uint256 zroFee);
}

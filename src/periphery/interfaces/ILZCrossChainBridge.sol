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

    /// @notice Thrown when there is nothing to rescue (zero balance).
    error LZCrossChainBridge_NothingToRescue();

    /// @notice Thrown when a native transfer fails during rescue.
    /// @param recipient The intended recipient.
    /// @param amount The amount attempted to transfer.
    error LZCrossChainBridge_NativeTransferFailed(address recipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens are rescued from the contract.
    /// @param token The rescued ERC20 token address.
    /// @param to The recipient address.
    /// @param amount The amount rescued.
    event Rescued(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when native token (ETH) is rescued from the contract.
    /// @param to The recipient address.
    /// @param amount The amount rescued.
    event NativeRescued(address indexed to, uint256 amount);

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

    /// @notice Rescues ERC20 tokens accidentally sent to this contract.
    /// @dev Only callable by the owner. Sweeps the entire token balance to the
    ///      provided recipient.
    ///
    /// @param token_ The ERC20 token to rescue.
    /// @param to_ The recipient of the rescued tokens.
    function rescue(address token_, address to_) external;

    /// @notice Rescues native token (ETH) accidentally sent to or stuck in this contract.
    /// @dev Only callable by the owner. Sweeps the entire native balance to the
    ///      provided recipient.
    ///
    /// @param to_ The recipient of the rescued native token.
    function rescueNative(address payable to_) external;

    /// @notice Returns the LZBridgeGateway address.
    function gateway() external view returns (address);

    /// @notice Returns the OHM token address.
    // solhint-disable-next-line func-name-mixedcase
    function OHM() external view returns (address);

    /// @notice Estimates the fee for sending OHM to a destination chain.
    /// @dev Proxies to the gateway's estimateSendFee function with empty extra options.
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
}

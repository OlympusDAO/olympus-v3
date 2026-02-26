// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ILZBridgeGateway
/// @notice Interface for the LZ Bridge Gateway, an infrastructure policy that handles all
///         communication with the LayerZero endpoint, performs OHM mint/burn via MINTR,
///         manages trusted remotes and the bridged supply cap, and routes incoming messages
///         by type (bridge OHM or governance).
interface ILZBridgeGateway {
    // ========= CORE FUNCTIONS ========= //

    /// @notice Burns OHM held by the gateway and sends a bridge message to a destination chain.
    /// @dev Only callable by the facilitator. The facilitator must transfer OHM to the gateway
    ///      before calling this function. The gateway burns the OHM via MINTR and sends a
    ///      LayerZero message.
    ///
    ///      On canonical chains (isCanonical == true), increments bridgedSupply and checks
    ///      against bridgedSupplyCap.
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
}

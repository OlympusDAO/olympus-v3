// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

/// @title ILZEndpointDelegate
/// @notice The external interface of an LZ Bridge endpoint delegate policy that acts as
///         a LayerZero V2 endpoint delegate for a specific LZBridgeGateway, exposing the
///         OApp-authorized endpoint surface via ILZEndpointV2Authorized.
/// @dev Implementations are designed to be assigned as the endpoint delegate of the gateway
///      so the LayerZero endpoint accepts the calls forwarded by this policy with the gateway
///      as the OApp argument.
interface ILZEndpointDelegate {
    // ========= VIEW FUNCTIONS ========= //

    /// @notice The LayerZero V2 endpoint address this delegate proxies to.
    // solhint-disable-next-line func-name-mixedcase
    function LZ_ENDPOINT() external view returns (address);

    /// @notice The address of the LZBridgeGateway this delegate acts on behalf of.
    // solhint-disable-next-line func-name-mixedcase
    function GATEWAY() external view returns (address);
}

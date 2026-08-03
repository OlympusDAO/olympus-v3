// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IEndpointV2State
/// @notice Minimal interface for accessing EndpointV2 public state that is not
///         exposed through ILayerZeroEndpointV2.
interface IEndpointV2State {
    /// @notice Returns the delegate address for a given OApp.
    function delegates(address oapp) external view returns (address);
}

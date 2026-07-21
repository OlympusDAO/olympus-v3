// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title ILayerZeroDVNState
/// @notice Minimal interface for querying DVN contract state on the LZ endpoint.
interface ILayerZeroDVNState {
    /// @notice Returns the DVN's vendor ID.
    function vid() external view returns (uint32);
}

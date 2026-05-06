// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";

/// @title IUlnConfigState
/// @notice Minimal view interface for accessing the raw (OApp-level, unresolved) UlnConfig
///         stored on a LayerZero V2 Send/Receive ULN library.
/// @dev Used to distinguish "inherit default" (`optionalDVNCount == 0`) from
///      "explicit NIL / no optional DVNs" (`optionalDVNCount == type(uint8).max`), which
///      look identical after the default-resolution performed by `getUlnConfig` (and by
///      `ILayerZeroEndpointV2.getConfig`).
interface IUlnConfigState {
    /// @notice Returns the raw UlnConfig stored for the given OApp and remote EID
    ///         (without applying the LayerZero default-config fallback).
    /// @param _oapp The OApp address.
    /// @param _remoteEid The remote endpoint ID.
    function getAppUlnConfig(
        address _oapp,
        uint32 _remoteEid
    ) external view returns (UlnConfig memory);
}

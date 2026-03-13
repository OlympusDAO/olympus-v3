// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Origin} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";

/// @title ILZEndpointV2Admin
/// @notice Interface for LayerZero endpoint v2 delegate-callable functions.
/// @dev LZ endpoints assume msg.sender is OApp, so a logic contract can always call these functions directly.
interface ILZEndpointV2Admin {
    // ========= LIBRARY MANAGEMENT ========= //

    /// @notice Pins send library for a destination EID.
    /// @param eid_ The destination endpoint ID.
    /// @param lib_ The send library address to pin.
    function setSendLibrary(uint32 eid_, address lib_) external;

    /// @notice Pins receive library for a source EID.
    /// @param eid_ The source endpoint ID.
    /// @param lib_ The receive library address to pin.
    /// @param gracePeriod_ Grace period for migration (0 for immediate).
    function setReceiveLibrary(uint32 eid_, address lib_, uint256 gracePeriod_) external;

    /// @notice Sets receive library timeout for migration.
    /// @param eid_ The source endpoint ID.
    /// @param lib_ The library address.
    /// @param expiry_ The expiry timestamp.
    function setReceiveLibraryTimeout(uint32 eid_, address lib_, uint256 expiry_) external;

    /// @notice Sets ULN/Executor config on a message library.
    /// @param lib_ The message library address.
    /// @param params_ Array of config parameters per EID.
    function setEndpointConfig(address lib_, SetConfigParam[] calldata params_) external;

    // ========= MESSAGE MANAGEMENT ========= //

    /// @notice Skips a nonce for a source path.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce to skip.
    function skip(uint32 srcEid_, bytes32 sender_, uint64 nonce_) external;

    /// @notice Nilifies a payload for a source path.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The hash of the payload to nilify.
    function nilify(uint32 srcEid_, bytes32 sender_, uint64 nonce_, bytes32 payloadHash_) external;

    /// @notice Burns a payload for a source path.
    /// @param srcEid_ The source endpoint ID.
    /// @param sender_ The sender address (bytes32).
    /// @param nonce_ The nonce of the message.
    /// @param payloadHash_ The hash of the payload to burn.
    function burn(uint32 srcEid_, bytes32 sender_, uint64 nonce_, bytes32 payloadHash_) external;

    /// @notice Clears a composed message.
    /// @param origin_ The origin of the message.
    /// @param guid_ The GUID of the message.
    /// @param message_ The message bytes.
    function clear(Origin calldata origin_, bytes32 guid_, bytes calldata message_) external;
}

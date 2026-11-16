// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MockLZBridgeGateway
/// @notice Minimal stand-in for `LZBridgeGateway` used by `LZEndpointDelegate` tests.
/// @dev Exposes only the `LZ_ENDPOINT()` view that `LZEndpointDelegate` reads in its constructor.
contract MockLZBridgeGateway {
    // solhint-disable-next-line var-name-mixedcase
    address public immutable LZ_ENDPOINT;

    constructor(address lzEndpoint_) {
        LZ_ENDPOINT = lzEndpoint_;
    }
}

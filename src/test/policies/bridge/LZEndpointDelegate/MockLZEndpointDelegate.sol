// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

/// @title MockLZEndpointDelegate
/// @notice Minimal stand-in for `LZEndpointDelegate` used by `LZBridgeActivator` constructor tests.
contract MockLZEndpointDelegate {
    // solhint-disable-next-line var-name-mixedcase
    address public immutable GATEWAY;
    // solhint-disable-next-line var-name-mixedcase
    address public immutable LZ_ENDPOINT;

    constructor(address gateway_, address lzEndpoint_) {
        GATEWAY = gateway_;
        LZ_ENDPOINT = lzEndpoint_;
    }
}

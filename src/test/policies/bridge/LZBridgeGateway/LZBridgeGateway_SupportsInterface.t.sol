// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {IRescuable} from "../../../../bases/interfaces/IRescuable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";

/// @dev ERC-165 interface detection.
contract LZBridgeGatewayTests_SupportsInterface is LZBridgeGatewayTestBase {
    function test_supportsInterface_ILZBridgeGateway() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZBridgeGateway).interfaceId),
            "Should support ILZBridgeGateway"
        );
    }

    function test_supportsInterface_ILZEndpointV2Admin() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZEndpointV2Admin).interfaceId),
            "Should support ILZEndpointV2Admin"
        );
    }

    function test_supportsInterface_ILayerZeroReceiver() external view {
        assertTrue(
            gateway.supportsInterface(type(ILayerZeroReceiver).interfaceId),
            "Should support ILayerZeroReceiver"
        );
    }

    function test_supportsInterface_IRescuable() external view {
        assertTrue(
            gateway.supportsInterface(type(IRescuable).interfaceId),
            "Should support IRescuable"
        );
    }

    function test_supportsInterface_IVersioned() external view {
        assertTrue(
            gateway.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_IEnabler() external view {
        assertTrue(
            gateway.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );
    }

    function test_supportsInterface_ERC165() external view {
        assertTrue(gateway.supportsInterface(bytes4(0x01ffc9a7)), "Should support ERC-165");
    }

    function test_supportsInterface_unsupported() external view {
        assertFalse(
            gateway.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

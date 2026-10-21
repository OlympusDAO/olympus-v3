// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Interfaces
import {ILayerZeroReceiver} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroReceiver.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {IRescueable} from "src/bases/interfaces/IRescueable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/bases/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/bases/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/bases/interfaces/IReEnabler.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

/// @dev ERC-165 interface detection.
contract LZBridgeGatewayTests_SupportsInterface is LZBridgeGatewayTestBase {
    function test_supportsInterface_validatesIERC165Self() external view {
        ERC165Helper.validateSupportsInterface(address(gateway));
    }

    function test_supportsInterface_returnsTrueForILZBridgeGateway() external view {
        assertTrue(
            gateway.supportsInterface(type(ILZBridgeGateway).interfaceId),
            "Should support ILZBridgeGateway"
        );
    }

    function test_supportsInterface_returnsTrueForILayerZeroReceiver() external view {
        assertTrue(
            gateway.supportsInterface(type(ILayerZeroReceiver).interfaceId),
            "Should support ILayerZeroReceiver"
        );
    }

    function test_supportsInterface_returnsTrueForIOffsettingRateLimiter() external view {
        assertTrue(
            gateway.supportsInterface(type(IOffsettingRateLimiter).interfaceId),
            "Should support IOffsettingRateLimiter"
        );
    }

    function test_supportsInterface_returnsTrueForIRescueable() external view {
        assertTrue(
            gateway.supportsInterface(type(IRescueable).interfaceId),
            "Should support IRescueable"
        );
    }

    function test_supportsInterface_returnsTrueForIVersioned() external view {
        assertTrue(
            gateway.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_returnsTrueForIEnabler() external view {
        assertTrue(
            gateway.supportsInterface(type(IEnabler).interfaceId),
            "Should support IEnabler"
        );
    }

    function test_supportsInterface_returnsTrueForIEnablerV2() external view {
        assertTrue(
            gateway.supportsInterface(type(IEnablerV2).interfaceId),
            "Should support IEnablerV2"
        );
    }

    function test_supportsInterface_returnsTrueForIReEnabler() external view {
        assertTrue(
            gateway.supportsInterface(type(IReEnabler).interfaceId),
            "Should support IReEnabler"
        );
    }

    function test_supportsInterface_returnsTrueForIGracePeriod() external view {
        assertTrue(
            gateway.supportsInterface(type(IGracePeriod).interfaceId),
            "Should support IGracePeriod"
        );
    }

    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(gateway.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_supportsInterface_returnsFalseForUnsupportedInterface() external view {
        assertFalse(
            gateway.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IRescuable} from "../../../../bases/interfaces/IRescuable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_SupportsInterface is LZCrossChainBridgeTestBase {
    function test_supportsInterface_ILZCrossChainBridge() external view {
        assertTrue(
            bridge.supportsInterface(type(ILZCrossChainBridge).interfaceId),
            "Should support ILZCrossChainBridge"
        );
    }

    function test_supportsInterface_IRescuable() external view {
        assertTrue(
            bridge.supportsInterface(type(IRescuable).interfaceId),
            "Should support IRescuable"
        );
    }

    function test_supportsInterface_IVersioned() external view {
        assertTrue(
            bridge.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_IEnabler() external view {
        assertTrue(bridge.supportsInterface(type(IEnabler).interfaceId), "Should support IEnabler");
    }

    function test_supportsInterface_ERC165() external view {
        assertTrue(bridge.supportsInterface(bytes4(0x01ffc9a7)), "Should support ERC-165");
    }

    function test_supportsInterface_unsupported() external view {
        assertFalse(
            bridge.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

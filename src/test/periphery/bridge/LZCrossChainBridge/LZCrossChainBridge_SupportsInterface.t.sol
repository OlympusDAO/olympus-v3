// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";
import {IEnablerV2GracePeriod} from "src/interfaces/IEnablerV2GracePeriod.sol";
import {IEnablerV2ReEnable} from "src/interfaces/IEnablerV2ReEnable.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

contract LZCrossChainBridgeTests_SupportsInterface is LZCrossChainBridgeTestBase {
    function test_supportsInterface_ILZCrossChainBridge() external view {
        assertTrue(
            bridge.supportsInterface(type(ILZCrossChainBridge).interfaceId),
            "Should support ILZCrossChainBridge"
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

    function test_supportsInterface_IEnablerV2() external view {
        assertTrue(
            bridge.supportsInterface(type(IEnablerV2).interfaceId),
            "Should support IEnablerV2"
        );
    }

    function test_supportsInterface_IEnablerV2ReEnable() external view {
        assertTrue(
            bridge.supportsInterface(type(IEnablerV2ReEnable).interfaceId),
            "Should support IEnablerV2ReEnable"
        );
    }

    function test_supportsInterface_IEnablerV2GracePeriod() external view {
        assertTrue(
            bridge.supportsInterface(type(IEnablerV2GracePeriod).interfaceId),
            "Should support IEnablerV2GracePeriod"
        );
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

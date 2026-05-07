// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZCrossChainBridgeTestBase} from "src/test/periphery/bridge/LZCrossChainBridge/LZCrossChainBridgeTestBase.sol";

// Interfaces
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IRescueable} from "src/bases/interfaces/IRescueable.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IEnablerV2} from "src/interfaces/IEnablerV2.sol";
import {IGracePeriod} from "src/interfaces/IGracePeriod.sol";
import {IReEnabler} from "src/interfaces/IReEnabler.sol";
import {ILZCrossChainBridge} from "src/periphery/interfaces/ILZCrossChainBridge.sol";

// Libraries
import {ERC165Helper} from "src/test/lib/ERC165.sol";

contract LZCrossChainBridgeTests_SupportsInterface is LZCrossChainBridgeTestBase {
    function test_supportsInterface_validatesIERC165Self() external view {
        ERC165Helper.validateSupportsInterface(address(bridge));
    }

    function test_supportsInterface_returnsTrueForILZCrossChainBridge() external view {
        assertTrue(
            bridge.supportsInterface(type(ILZCrossChainBridge).interfaceId),
            "Should support ILZCrossChainBridge"
        );
    }

    function test_supportsInterface_returnsTrueForIRescueable() external view {
        assertTrue(
            bridge.supportsInterface(type(IRescueable).interfaceId),
            "Should support IRescueable"
        );
    }

    function test_supportsInterface_returnsTrueForIVersioned() external view {
        assertTrue(
            bridge.supportsInterface(type(IVersioned).interfaceId),
            "Should support IVersioned"
        );
    }

    function test_supportsInterface_returnsTrueForIEnabler() external view {
        assertTrue(bridge.supportsInterface(type(IEnabler).interfaceId), "Should support IEnabler");
    }

    function test_supportsInterface_returnsTrueForIEnablerV2() external view {
        assertTrue(
            bridge.supportsInterface(type(IEnablerV2).interfaceId),
            "Should support IEnablerV2"
        );
    }

    function test_supportsInterface_returnsTrueForIReEnabler() external view {
        assertTrue(
            bridge.supportsInterface(type(IReEnabler).interfaceId),
            "Should support IReEnabler"
        );
    }

    function test_supportsInterface_returnsTrueForIGracePeriod() external view {
        assertTrue(
            bridge.supportsInterface(type(IGracePeriod).interfaceId),
            "Should support IGracePeriod"
        );
    }

    function test_supportsInterface_returnsTrueForIERC165() external view {
        assertTrue(bridge.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    }

    function test_supportsInterface_returnsFalseForUnsupportedInterface() external view {
        assertFalse(
            bridge.supportsInterface(bytes4(0xdeadbeef)),
            "Should not support random interface"
        );
    }
}

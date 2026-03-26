// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Contracts
import {Permissions, Keycode} from "src/Kernel.sol";

contract LZBridgeGatewayTests_PolicySetup is LZBridgeGatewayTestBase {
    function test_configureDependencies() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should be set");
        assertEq(gateway.ohm(), address(ohm), "OHM address should be set from MINTR");
    }

    function test_requestPermissions() external view {
        Permissions[] memory perms = gateway.requestPermissions();

        assertEq(perms.length, 3, "Should request 3 permissions");
        // All three should be on MINTR keycode
        assertEq(
            Keycode.unwrap(perms[0].keycode),
            bytes5("MINTR"),
            "Permission 0 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[1].keycode),
            bytes5("MINTR"),
            "Permission 1 should be on MINTR"
        );
        assertEq(
            Keycode.unwrap(perms[2].keycode),
            bytes5("MINTR"),
            "Permission 2 should be on MINTR"
        );
    }

    function test_VERSION() external view {
        (uint8 major, uint8 minor) = gateway.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}

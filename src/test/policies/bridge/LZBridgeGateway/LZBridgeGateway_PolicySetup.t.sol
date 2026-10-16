// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeGatewayTestBase} from "src/test/policies/bridge/LZBridgeGateway/LZBridgeGatewayTestBase.sol";

// Contracts
import {Permissions, Keycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";

contract LZBridgeGatewayTests_PolicySetup is LZBridgeGatewayTestBase {
    function test_configureDependencies() external view {
        assertEq(address(gateway.MINTR()), address(mintr), "MINTR should be set");
        assertEq(gateway.ohm(), address(ohm), "OHM address should be set from MINTR");
    }

    function test_requestPermissions() external view {
        Permissions[] memory perms = gateway.requestPermissions();

        assertEq(perms.length, 4, "Should request 4 permissions");
        // All four should be on MINTR keycode
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
        assertEq(
            Keycode.unwrap(perms[3].keycode),
            bytes5("MINTR"),
            "Permission 3 should be on MINTR"
        );

        // Verify funcSelectors target the correct MINTR functions
        assertEq(
            perms[0].funcSelector,
            MINTRv1.mintOhm.selector,
            "Permission 0 should target mintOhm"
        );
        assertEq(
            perms[1].funcSelector,
            MINTRv1.burnOhm.selector,
            "Permission 1 should target burnOhm"
        );
        assertEq(
            perms[2].funcSelector,
            MINTRv1.increaseMintApproval.selector,
            "Permission 2 should target increaseMintApproval"
        );
        assertEq(
            perms[3].funcSelector,
            MINTRv1.decreaseMintApproval.selector,
            "Permission 3 should target decreaseMintApproval"
        );
    }

    function test_VERSION() external view {
        (uint8 major, uint8 minor) = gateway.VERSION();
        assertEq(major, 1, "Major version should be 1");
        assertEq(minor, 0, "Minor version should be 0");
    }
}

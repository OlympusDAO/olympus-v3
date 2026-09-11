// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.30;

import {LZBridgeAndDelegateConfigTestBase} from "src/test/policies/bridge/LZBridgeAndDelegateConfig/LZBridgeAndDelegateConfigTestBase.sol";

// Contracts
import {Permissions} from "src/Kernel.sol";

contract LZBridgeAndDelegateConfigTests_PolicySetup is LZBridgeAndDelegateConfigTestBase {
    function test_configureDependencies_resolvesRoles() external view {
        // The setUp activated the policy; the ROLES module accessor must be populated.
        assertEq(
            address(config.ROLES()),
            address(roles),
            "ROLES dependency should resolve to the canonical roles module"
        );
    }

    function test_requestPermissions_returnsEmpty() external view {
        Permissions[] memory perms = config.requestPermissions();
        assertEq(perms.length, 0, "config policy should not request any Kernel permissions");
    }

    function test_VERSION_returns1_0() external view {
        (uint8 major, uint8 minor) = config.VERSION();
        assertEq(uint256(major), 1, "major should be 1");
        assertEq(uint256(minor), 0, "minor should be 0");
    }
}
